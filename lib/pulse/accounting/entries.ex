defmodule Pulse.Accounting.Entries do
  @moduledoc """
  Публичный API записи проводок (раздел 5.4 ТЗ).

  Документные домены пишут проводки только через этот модуль: прямая
  запись в `journal_entries` запрещена, иначе теряется контроль над
  инвариантами (дебет равен кредиту, период, валюта, количество).

  Функции вызываются из `Pulse.Accounting.Posting` внутри уже открытой
  транзакции документа, поэтому собственных транзакций не открывают.
  """
  require Ash.Query

  alias Pulse.Accounting.JournalEntry

  @doc """
  Записывает проводки документа.

  Принимает список карт; `organization_id`, `document_type`, `document_id`
  подставляются из документа, чтобы вызывающий код не дублировал их.
  Проверка «дебет = кредит» выполняется по итогам всех проводок документа.
  """
  @spec write(struct(), [map()]) :: :ok | {:error, term()}
  def write(document, entries) when is_list(entries) do
    with :ok <- validate_balanced(entries) do
      entries
      |> Enum.map(&prepare(document, &1))
      |> reduce_results(&create(&1, document.organization_id))
    end
  end

  @doc """
  Удаляет проводки документа.

  Вызывается при отмене проведения: проводки уходят вместе с движениями.
  """
  @spec delete(struct()) :: :ok | {:error, term()}
  def delete(document) do
    type = Pulse.Accounting.Posting.document_type(document)

    query =
      JournalEntry
      |> Ash.Query.filter(document_type == ^type and document_id == ^document.id)

    with {:ok, entries} <- Ash.read(query, tenant: document.organization_id, authorize?: false) do
      reduce_results(entries, &purge(&1, document))
    end
  end

  @doc """
  Проводки документа, упорядоченные по дате и времени записи.
  """
  @spec for_document(struct()) :: [JournalEntry.t()]
  def for_document(document) do
    type = Pulse.Accounting.Posting.document_type(document)

    query =
      JournalEntry
      |> Ash.Query.filter(document_type == ^type and document_id == ^document.id)
      |> Ash.Query.sort(inserted_at: :asc)

    case Ash.read(query, tenant: document.organization_id, authorize?: false) do
      {:ok, entries} -> entries
      _ -> []
    end
  end

  @doc """
  Проверяет, что сумма дебета равна сумме кредита по набору проводок.

  Инвариант раздела 5.2 ТЗ: по каждому документу дебет равен кредиту.
  Каждая проводка даёт одинаковую сумму в дебет и в кредит, поэтому
  проверка сводится к тому, что все суммы положительны и корректны.
  """
  @spec validate_balanced([map()]) :: :ok | {:error, String.t()}
  def validate_balanced(entries) do
    case Enum.find(entries, &(not valid_amount?(&1[:amount]))) do
      nil -> :ok
      entry -> {:error, "некорректная сумма проводки: #{inspect(entry[:amount])}"}
    end
  end

  defp valid_amount?(%Decimal{} = amount), do: Decimal.compare(amount, 0) == :gt
  defp valid_amount?(_amount), do: false

  @doc """
  Остаток и обороты по счёту за период — из проводок.

  Остаток на начало считается по проводкам до начала периода, обороты —
  внутри периода. Это основа ОСВ, карточки и анализа счёта.
  """
  @spec turnover(String.t(), String.t(), Date.t(), Date.t(), keyword()) :: map()
  def turnover(account_code, organization_id, from, to, opts \\ []) do
    ledger = Keyword.get(opts, :ledger, :accounting)

    {:ok, before} =
      read_entries(organization_id, ledger, nil, Date.add(from, -1))

    {:ok, within} = read_entries(organization_id, ledger, from, to)

    opening = balance(before, account_code)
    turnover = turnover_of(within, account_code)

    %{
      account_code: account_code,
      opening: opening,
      debit_turnover: turnover.debit,
      credit_turnover: turnover.credit,
      closing: closing(opening, turnover)
    }
  end

  @doc """
  Все проводки организации за период по виду учёта.

  Основа отчёта по проводкам: `ledger` разделяет бухгалтерский
  (`:accounting`) и налоговый (`:tax`) учёт.
  """
  @spec entries(String.t(), Date.t(), Date.t(), keyword()) :: [JournalEntry.t()]
  def entries(organization_id, from, to, opts \\ []) do
    ledger = Keyword.get(opts, :ledger, :accounting)

    case read_entries(organization_id, ledger, from, to) do
      {:ok, entries} -> entries
      _ -> []
    end
  end

  @doc """
  Проводки по счёту за период (для карточки и анализа счёта).
  """
  @spec entries_for_account(String.t(), String.t(), Date.t(), Date.t(), keyword()) ::
          [JournalEntry.t()]
  def entries_for_account(account_code, organization_id, from, to, opts \\ []) do
    ledger = Keyword.get(opts, :ledger, :accounting)

    case read_entries(organization_id, ledger, from, to) do
      {:ok, entries} -> Enum.filter(entries, &touches?(&1, account_code))
      _ -> []
    end
  end

  defp read_entries(organization_id, ledger, from, to) do
    query =
      JournalEntry
      |> Ash.Query.filter(ledger == ^ledger)
      |> filter_dates(from, to)
      |> Ash.Query.sort(doc_date: :asc, inserted_at: :asc)

    Ash.read(query, tenant: organization_id, authorize?: false)
  end

  defp filter_dates(query, nil, to), do: Ash.Query.filter(query, doc_date <= ^to)

  defp filter_dates(query, from, to),
    do: Ash.Query.filter(query, doc_date >= ^from and doc_date <= ^to)

  defp touches?(entry, account_code) do
    entry.debit_account_code == account_code or entry.credit_account_code == account_code
  end

  defp balance(entries, account_code) do
    Enum.reduce(entries, %{debit: zero(), credit: zero()}, fn entry, acc ->
      cond do
        entry.debit_account_code == account_code ->
          %{acc | debit: Decimal.add(acc.debit, entry.amount)}

        entry.credit_account_code == account_code ->
          %{acc | credit: Decimal.add(acc.credit, entry.amount)}

        true ->
          acc
      end
    end)
  end

  defp turnover_of(entries, account_code) do
    Enum.reduce(entries, %{debit: zero(), credit: zero()}, fn entry, acc ->
      debit = if entry.debit_account_code == account_code, do: entry.amount, else: zero()
      credit = if entry.credit_account_code == account_code, do: entry.amount, else: zero()

      %{
        debit: Decimal.add(acc.debit, debit),
        credit: Decimal.add(acc.credit, credit)
      }
    end)
  end

  defp closing(opening, turnover) do
    %{
      debit: Decimal.add(opening.debit, turnover.debit),
      credit: Decimal.add(opening.credit, turnover.credit)
    }
  end

  defp prepare(document, entry) do
    entry
    |> Map.put_new(:period, period(document.doc_date))
    |> Map.put_new(:doc_date, document.doc_date)
    |> Map.put_new(:ledger, :accounting)
    |> Map.put_new(:debit_subaccounts, [])
    |> Map.put_new(:credit_subaccounts, [])
    |> Map.put(:organization_id, document.organization_id)
    |> Map.put(:document_type, Pulse.Accounting.Posting.document_type(document))
    |> Map.put(:document_id, document.id)
  end

  defp create(attrs, organization_id) do
    JournalEntry
    |> Ash.Changeset.for_create(:create, attrs)
    |> Ash.Changeset.set_tenant(organization_id)
    |> Ash.create(authorize?: false)
    |> case do
      {:ok, _entry} -> :ok
      {:error, error} -> {:error, error}
    end
  end

  defp purge(entry, document) do
    entry
    |> Ash.Changeset.for_destroy(:purge)
    |> Ash.Changeset.set_tenant(document.organization_id)
    |> Ash.destroy(authorize?: false)
    |> case do
      :ok -> :ok
      {:error, error} -> {:error, error}
    end
  end

  # Выполняет действие по очереди, останавливаясь на первой ошибке.
  defp reduce_results(items, fun) do
    Enum.reduce_while(items, :ok, fn item, :ok ->
      case fun.(item) do
        :ok -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp zero, do: Decimal.new(0)

  # Первый день месяца документа — помесячный разрез для итогов.
  defp period(%Date{year: year, month: month}), do: %Date{year: year, month: month, day: 1}
end
