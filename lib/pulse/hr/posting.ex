defmodule Pulse.HR.Posting do
  @moduledoc """
  Проведение кадровых документов (раздел 5.5 ТЗ).

  Кадровый документ не пишет проводок и не двигает деньги: он меняет
  карточку сотрудника. Поэтому у него собственный цикл проведения —
  тот же контракт, что у `Pulse.Accounting.Posting` (проверить статус и
  период, применить, отметить проведённым в одной транзакции), но без
  регистров учёта.

  Отмена возвращает карточку к состоянию из снимка `snapshot`, который
  документ сохраняет при проведении.
  """
  require Ash.Query

  alias Pulse.HR.Employee

  @doc """
  Проводит кадровый документ.
  """
  @spec post(struct(), struct()) :: {:ok, struct()} | {:error, term()}
  def post(document, actor) do
    run(document, actor, :post)
  end

  @doc """
  Проведение с совместимой подписью правил бухгалтерского проведения.

  Кадровые документы не пишут проводок, поэтому правило игнорируется:
  так журнал документов вызывает их единообразно.
  """
  @spec post(struct(), struct(), module()) :: {:ok, struct()} | {:error, term()}
  def post(document, actor, _rule), do: post(document, actor)

  @doc """
  Отменяет проведение кадрового документа.
  """
  @spec unpost(struct(), struct(), module()) :: {:ok, struct()} | {:error, term()}
  def unpost(document, actor, _rule) do
    run(document, actor, :unpost)
  end

  defp run(document, actor, mode) do
    with :ok <- check_status(document, mode),
         :ok <- check_period(document, actor),
         {:ok, result} <- transaction(document, actor, mode) do
      broadcast(document, mode)
      {:ok, result}
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

  defp check_period(%{doc_date: date, organization_id: organization_id}, actor) do
    Pulse.Accounting.Periods.check(date, organization_id, actor && actor.role)
  end

  defp transaction(document, actor, mode) do
    Pulse.Repo.transaction(fn ->
      with {:ok, effect} <- apply_effect(document, mode),
           {:ok, updated} <- mark(document, effect, actor, mode) do
        updated
      else
        {:error, error} -> Pulse.Repo.rollback(error)
      end
    end)
    |> case do
      {:ok, updated} -> {:ok, updated}
      {:error, error} -> {:error, error}
    end
  end

  # При проведении карточка меняется по документу, при отмене —
  # возвращается к снимку, сохранённому при проведении.
  defp apply_effect(document, :post) do
    attrs = effect_attrs(document)

    case employee(document) do
      nil -> {:ok, %{document: attrs, employee: nil}}
      employee -> {:ok, %{document: attrs, employee: employee}}
    end
  end

  defp apply_effect(%{snapshot: snapshot}, :unpost) do
    {:ok, %{document: %{}, employee: snapshot}}
  end

  # Что именно меняет документ в карточке сотрудника.
  defp effect_attrs(%{kind: :hiring} = document) do
    %{
      person_id: document.person_id,
      position_id: document.position_id,
      department_id: document.department_id,
      salary: document.salary,
      hire_date: document.doc_date,
      status: :working
    }
  end

  defp effect_attrs(%{kind: :transfer} = document) do
    %{
      position_id: document.position_id,
      department_id: document.department_id,
      salary: document.salary
    }
  end

  defp effect_attrs(%{kind: :dismissal} = document) do
    %{dismissal_date: document.doc_date, status: :dismissed}
  end

  defp effect_attrs(%{kind: :trip} = document) do
    %{
      trip_from: document.trip_from,
      trip_to: document.trip_to,
      trip_destination: document.trip_destination
    }
  end

  # При проведении карточка обновляется (или создаётся при приёме),
  # при отмене — возвращается к снимку.
  defp mark(document, effect, actor, :post) do
    # Снимок берётся до применения документа: отмена вернёт карточку
    # к состоянию на момент проведения.
    previous = current_snapshot(document, effect)

    with {:ok, employee} <- apply_employee(document, effect) do
      update_document(document, employee, previous, actor, :post)
    end
  end

  defp mark(document, effect, actor, :unpost) do
    with {:ok, _employee} <- restore_employee(document, effect) do
      update_document(document, nil, nil, actor, :unpost)
    end
  end

  # Снимок карточки до проведения: при приёме сотрудника ещё нет.
  defp current_snapshot(_document, %{employee: %Employee{} = employee}), do: snapshot(employee)
  defp current_snapshot(_document, _effect), do: nil

  # Приём создаёт сотрудника, остальные документы обновляют карточку.
  defp apply_employee(%{kind: :hiring, employee_id: nil} = document, _effect) do
    document
    |> effect_attrs()
    |> then(&Ash.Changeset.for_create(Employee, :create, &1))
    |> Ash.Changeset.set_tenant(document.organization_id)
    |> Ash.create(authorize?: false, tenant: document.organization_id)
    |> case do
      {:ok, employee} -> {:ok, employee}
      {:error, error} -> {:error, error}
    end
  end

  defp apply_employee(document, %{employee: employee}) do
    employee
    |> employee_changeset(document)
  end

  defp employee_changeset(nil, _document), do: {:ok, nil}

  defp employee_changeset(%Employee{} = employee, document) do
    employee
    |> Ash.Changeset.for_update(:update, effect_attrs(document))
    |> Ash.Changeset.set_tenant(document.organization_id)
    |> Ash.update(authorize?: false, tenant: document.organization_id)
    |> case do
      {:ok, updated} -> {:ok, updated}
      {:error, error} -> {:error, error}
    end
  end

  # Отмена возвращает карточку к снимку, сделанному при проведении.
  defp restore_employee(%{kind: :hiring, employee_id: nil}, _effect), do: {:ok, nil}

  defp restore_employee(document, %{employee: snapshot}) when is_map(snapshot) do
    case employee(document) do
      nil ->
        {:ok, nil}

      %Employee{} = employee ->
        attrs =
          snapshot
          |> normalize_snapshot()
          |> decode_snapshot()

        employee
        |> Ash.Changeset.for_update(:update, attrs)
        |> Ash.Changeset.set_tenant(document.organization_id)
        |> Ash.update(authorize?: false, tenant: document.organization_id)
        |> case do
          {:ok, updated} -> {:ok, updated}
          {:error, error} -> {:error, error}
        end
    end
  end

  defp restore_employee(_document, _effect), do: {:ok, nil}

  # Снимок читается из jsonb со строковыми ключами; приводим к атомным,
  # чтобы дальше работать одинаково.
  defp normalize_snapshot(snapshot) do
    Map.new(snapshot, fn {key, value} -> {to_atom(key), value} end)
  end

  defp to_atom(key) when is_atom(key), do: key
  defp to_atom(key), do: String.to_existing_atom(key)

  defp decode_snapshot(snapshot) do
    snapshot
    |> Map.put(:salary, decode_decimal(snapshot[:salary]))
    |> Map.put(:hire_date, decode_date(snapshot[:hire_date]))
    |> Map.put(:dismissal_date, decode_date(snapshot[:dismissal_date]))
    |> Map.put(:status, decode_status(snapshot[:status]))
    |> Map.drop([:employee, :document])
  end

  defp decode_decimal(nil), do: nil
  defp decode_decimal(%Decimal{} = value), do: value
  defp decode_decimal(value), do: Decimal.new(value)

  defp decode_date(nil), do: nil
  defp decode_date(%Date{} = date), do: date
  defp decode_date(value), do: Date.from_iso8601!(value)

  defp decode_status(nil), do: nil
  defp decode_status(value) when is_atom(value), do: value
  defp decode_status(value), do: String.to_existing_atom(value)

  defp update_document(document, employee, snapshot, actor, :post) do
    document
    |> Ash.Changeset.for_update(:mark_posted, %{
      status: :posted,
      posted_at: DateTime.utc_now(),
      posted_by: actor && actor.id,
      snapshot: snapshot,
      employee_id: employee && employee.id
    })
    |> Ash.Changeset.set_tenant(document.organization_id)
    |> Ash.update(authorize?: false, tenant: document.organization_id)
  end

  defp update_document(document, _employee, _snapshot, _actor, :unpost) do
    document
    |> Ash.Changeset.for_update(:mark_draft, %{status: :draft, posted_at: nil, posted_by: nil})
    |> Ash.Changeset.set_tenant(document.organization_id)
    |> Ash.update(authorize?: false, tenant: document.organization_id)
  end

  defp employee(%{employee_id: nil}), do: nil

  defp employee(%{employee_id: id, organization_id: organization_id}),
    do: load_employee(id, organization_id)

  defp load_employee(id, organization_id) do
    Employee
    |> Ash.Query.filter(id == ^id)
    |> Ash.read_one(tenant: organization_id, authorize?: false)
    |> case do
      {:ok, employee} -> employee
      _ -> nil
    end
  end

  # Снимок полей карточки, которые меняют кадровые документы.
  defp snapshot(employee) do
    %{
      position_id: employee.position_id,
      department_id: employee.department_id,
      salary: employee.salary && Decimal.to_string(employee.salary),
      hire_date: employee.hire_date && Date.to_string(employee.hire_date),
      dismissal_date: employee.dismissal_date && Date.to_string(employee.dismissal_date),
      status: to_string(employee.status)
    }
  end

  defp broadcast(document, mode) do
    event = if mode == :post, do: :document_posted, else: :document_unposted

    Phoenix.PubSub.broadcast(
      Pulse.PubSub,
      "ledger:#{document.organization_id}",
      {event, document.__struct__, document.id}
    )
  end
end
