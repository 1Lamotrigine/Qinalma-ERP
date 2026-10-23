defmodule Pulse.Accounting.Posting do
  @moduledoc """
  Проведение и отмена проведения документов (раздел 5.3 ТЗ).

  Алгоритм:

    1. документ должен быть в статусе `draft` (или `posted` для отмены);
    2. период не закрыт, дата не раньше даты запрета (`period_locks`);
    3. `pg_advisory_xact_lock` по ключам (организация, склад, номенклатура)
       в отсортированном порядке — иначе взаимные блокировки;
    4. для расходных документов проверяются остатки;
    5. себестоимость считается по средней взвешенной;
    6. движения формирует чистая функция `Pulse.Posting.<ТипДокумента>`
       (проверяется без БД);
    7. движения, статус и аудит пишутся в одной транзакции;
    8. событие в PubSub уходит после коммита.

  Правила по типам документов — это модули, реализующие поведение
  `Pulse.Posting.Rule`: на вход документ, на выход список движений
  и — если документ ведёт бухгалтерский учёт — список проводок.
  """
  require Ash.Query
  require Logger

  alias Pulse.Accounting.Entries
  alias Pulse.Posting.Context

  @doc """
  Проводит документ: формирует движения и меняет статус.

  Возвращает `{:ok, документ}` либо `{:error, ошибка}`. Всё, включая
  аудит, выполняется в одной транзакции.
  """
  @spec post(struct(), struct(), module()) :: {:ok, struct()} | {:error, term()}
  def post(document, actor, rule) do
    run(document, actor, rule, :post)
  end

  @doc """
  Отменяет проведение: удаляет движения и возвращает статус `draft`.
  """
  @spec unpost(struct(), struct(), module()) :: {:ok, struct()} | {:error, term()}
  def unpost(document, actor, rule) do
    run(document, actor, rule, :unpost)
  end

  defp run(document, actor, rule, mode) do
    with :ok <- check_status(document, mode),
         :ok <- check_period(document, actor) do
      document
      |> transaction(actor, rule, mode)
      |> finish(mode)
    end
  end

  defp transaction(document, actor, rule, mode) do
    Pulse.Repo.transaction(fn ->
      lock(document, rule, mode)

      case mode do
        :post -> do_post(document, actor, rule)
        :unpost -> do_unpost(document, actor)
      end
    end)
  end

  defp finish({:ok, {:ok, document}}, mode) do
    broadcast(document, mode)
    schedule_backdated_recalculation(document, mode)
    {:ok, document}
  end

  defp finish({:ok, {:error, error}}, _mode), do: {:error, error}

  defp finish({:error, error}, _mode) do
    Logger.error("Проведение отменено: #{inspect(error)}")
    {:error, error}
  end

  # Проведение задним числом меняет себестоимость последующих расходов
  # месяца: движения считались по старой средней. Пересчёт уходит в фон,
  # чтобы не задерживать ответ пользователю.
  defp schedule_backdated_recalculation(document, mode) when mode in [:post, :unpost] do
    if backdated?(document) do
      _ = Pulse.Workers.RecalculateMonth.enqueue(document.doc_date, document.organization_id)
    end

    :ok
  end

  defp backdated?(%{doc_date: %Date{} = date}) do
    Date.compare(date, Date.utc_today()) == :lt
  end

  defp backdated?(_document), do: false

  defp do_post(document, actor, rule) do
    with :ok <- check_balances(document, rule) do
      context = Context.build(document, actor)

      with {:ok, registers} <- Pulse.Posting.Rule.ledger_movements(rule, document, context),
           :ok <- write_movements(document, registers),
           {:ok, entries} <- Pulse.Posting.Rule.entries_or_none(rule, document, context),
           :ok <- Entries.write(document, entries) do
        mark_posted(document, actor)
      end
    end
  end

  defp do_unpost(document, actor) do
    with :ok <- delete_movements(document),
         :ok <- Entries.delete(document) do
      mark_draft(document, actor)
    end
  end

  defp check_status(%{status: :draft}, :post), do: :ok

  defp check_status(%{status: status}, :post) do
    {:error, "документ уже в статусе «#{status}» — проведение невозможно"}
  end

  defp check_status(%{status: :posted}, :unpost), do: :ok

  defp check_status(%{status: status}, :unpost) do
    {:error, "отменить можно только проведённый документ (статус «#{status}»)"}
  end

  # Период проверяется с учётом роли: главный бухгалтер и администратор
  # обходят дату запрета, но закрытый месяц закрыт для всех.
  defp check_period(%{doc_date: date, organization_id: organization_id}, actor) do
    Pulse.Accounting.Periods.check(date, organization_id, actor && actor.role)
  end

  # Блокировки берутся в отсортированном порядке: сначала организация,
  # затем склад, затем номенклатура — так параллельные проведения
  # не блокируют друг друга насмерть.
  defp lock(document, rule, mode) do
    keys =
      [{:organization, document.organization_id}] ++
        rule.lock_keys(document, mode)

    keys
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.each(&advisory_lock/1)
  end

  defp advisory_lock(key) do
    hash = :erlang.phash2(key, 2_147_483_647)
    Ecto.Adapters.SQL.query!(Pulse.Repo, "SELECT pg_advisory_xact_lock($1)", [hash])
  end

  defp check_balances(document, rule) do
    case rule.check_balances(document) do
      :ok -> :ok
      {:error, message} -> {:error, message}
    end
  end

  # Записывает движения во все регистры документа в одной транзакции.
  defp write_movements(document, registers) do
    Enum.reduce_while(registers, :ok, fn {resource, movements}, :ok ->
      case write_register(document, resource, movements) do
        :ok -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp write_register(document, resource, movements) do
    Enum.reduce_while(movements, :ok, fn movement, :ok ->
      changeset =
        resource
        |> Ash.Changeset.for_create(
          :create,
          Map.put(movement, :organization_id, document.organization_id)
        )
        |> Ash.Changeset.set_tenant(document.organization_id)

      case Ash.create(changeset, authorize?: false) do
        {:ok, _movement} -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  # Движения удаляются из всех регистров, которые могли их получить:
  # регистр документа определяется его наличием, а не типом.
  defp delete_movements(document) do
    registers()
    |> Enum.reduce_while(:ok, fn resource, :ok ->
      case purge_register(document, resource) do
        :ok -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp purge_register(document, resource) do
    type = document_type(document)

    query =
      resource
      |> Ash.Query.filter(document_type == ^type and document_id == ^document.id)

    with {:ok, movements} <- Ash.read(query, tenant: document.organization_id, authorize?: false) do
      purge_all(movements, document)
    end
  end

  # Все регистры учёта: движения ТМЗ, деньги и взаиморасчёты.
  defp registers do
    [
      Pulse.Ledger.StockMovement,
      Pulse.Ledger.CashMovement,
      Pulse.Ledger.SettlementMovement,
      Pulse.Ledger.PayrollMovement
    ]
  end

  defp purge_all(movements, document) do
    Enum.reduce_while(movements, :ok, fn movement, :ok ->
      case purge(movement, document) do
        :ok -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp purge(movement, document) do
    movement
    |> Ash.Changeset.for_destroy(:purge)
    |> Ash.Changeset.set_tenant(document.organization_id)
    |> Ash.destroy(authorize?: false)
  end

  defp mark_posted(document, actor) do
    document
    |> Ash.Changeset.for_update(:mark_posted, %{
      status: :posted,
      posted_at: DateTime.utc_now(),
      posted_by: actor && actor.id
    })
    |> Ash.Changeset.set_tenant(document.organization_id)
    |> Ash.update(authorize?: false)
  end

  defp mark_draft(document, actor) do
    _ = actor

    document
    |> Ash.Changeset.for_update(:mark_draft, %{status: :draft, posted_at: nil, posted_by: nil})
    |> Ash.Changeset.set_tenant(document.organization_id)
    |> Ash.update(authorize?: false)
  end

  @doc """
  Тип документа в движениях: `Pulse.Purchasing.Receipt` → `"purchasing.receipt"`.
  """
  @spec document_type(struct()) :: String.t()
  def document_type(document) do
    document.__struct__
    |> Module.split()
    |> Enum.drop_while(&(&1 != "Pulse"))
    |> Enum.drop(1)
    |> Enum.map_join(".", &Macro.underscore/1)
  end

  defp broadcast(document, mode) do
    event = if mode == :post, do: :document_posted, else: :document_unposted

    Phoenix.PubSub.broadcast(
      Pulse.PubSub,
      "ledger:#{document.organization_id}",
      {event, document.__struct__, document.id}
    )
  end

  @doc """
  Движения документа из всех регистров: ТМЗ, деньги, взаиморасчёты.
  """
  @spec movements(struct()) :: [struct()]
  def movements(document) do
    type = document_type(document)

    registers()
    |> Enum.flat_map(fn resource ->
      query =
        resource
        |> Ash.Query.filter(document_type == ^type and document_id == ^document.id)
        |> Ash.Query.sort(inserted_at: :asc)

      case Ash.read(query, tenant: document.organization_id, authorize?: false) do
        {:ok, movements} -> movements
        _ -> []
      end
    end)
  end

  @doc false
  def ledger_module, do: Pulse.Ledger
end
