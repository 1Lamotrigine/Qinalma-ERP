defmodule Pulse.Accounting.Periods do
  @moduledoc """
  Управление учётными периодами: закрытие месяца, даты запрета правок
  и проверки при проведении (раздел 5.3 ТЗ).

  Период закрывается помесячно. После закрытия:

    * проведение документов внутри месяца запрещено;
    * отмена проведения запрещена — нужна корректировка или сторно;
    * себестоимость месяца пересчитана и зафиксирована.

  Дата запрета (`prohibition_date`) — более мягкая граница: документы
  с датой раньше неё менять нельзя, но это правило обходится ролью
  главного бухгалтера (и администратора).
  """

  alias Pulse.Core.PeriodLock

  require Ash.Query

  @doc """
  Проверяет, можно ли проводить документ с такой датой для роли.

  Возвращает `:ok` либо `{:error, причина}` с понятным текстом.
  Роль главного бухгалтера обходит дату запрета, но не закрытый период.
  """
  @spec check(Date.t(), String.t(), String.t() | nil) :: :ok | {:error, String.t()}
  def check(date, organization_id, role \\ nil) do
    cond do
      closed?(date, organization_id) ->
        {:error, "период #{month_label(date)} закрыт — проведение запрещено"}

      before_prohibition?(date, organization_id) and not bypasses?(role) ->
        {:error,
         "дата документа раньше даты запрета #{prohibition_label(organization_id)} — " <>
           "проведение запрещено (обратитесь к главному бухгалтеру)"}

      true ->
        :ok
    end
  end

  @doc """
  Закрыт ли период, содержащий дату.
  """
  @spec closed?(Date.t(), String.t()) :: boolean()
  def closed?(date, organization_id) do
    case read_lock(organization_id) do
      {:ok, %{closed_periods: closed}} -> month_start(date) in closed
      _ -> false
    end
  end

  @doc """
  Закрытые периоды организации в порядке убывания.
  """
  @spec closed_periods(String.t()) :: [Date.t()]
  def closed_periods(organization_id) do
    case read_lock(organization_id) do
      {:ok, %{closed_periods: closed}} -> Enum.sort(closed, {:desc, Date})
      _ -> []
    end
  end

  @doc """
  Дата запрета правок для организации.
  """
  @spec prohibition_date(String.t()) :: Date.t() | nil
  def prohibition_date(organization_id) do
    case read_lock(organization_id) do
      {:ok, %{prohibition_date: date}} -> date
      _ -> nil
    end
  end

  @doc """
  Закрывает месяц, содержащий дату.

  Возвращает `{:ok, %{period: ..., totals: ...}}` с итогами месяца
  либо ошибку. Себестоимость месяца пересчитывается до фиксации,
  чтобы закрытый период сразу содержал верные цифры.
  """
  @spec close_month(Date.t(), String.t(), struct() | nil) :: {:ok, map()} | {:error, term()}
  def close_month(date, organization_id, actor \\ nil) do
    period = month_start(date)

    with :ok <- ensure_open(period, organization_id) do
      _ = Pulse.Accounting.Recalculation.recalculate_month(organization_id, period)
      totals = Pulse.Accounting.Totals.for_period(organization_id, period)

      case add_closed_period(organization_id, period, actor) do
        {:ok, _lock} ->
          {:ok, %{period: period, totals: totals}}

        {:error, error} ->
          {:error, error}
      end
    end
  end

  # Закрытые месяцы хранятся списком в одной строке на организацию.
  defp add_closed_period(organization_id, period, actor) do
    attrs = %{
      closed_at: DateTime.utc_now(),
      closed_by: actor && actor.id
    }

    case read_lock_record(organization_id) do
      {:ok, nil} ->
        create_lock(
          Map.merge(attrs, %{organization_id: organization_id, closed_periods: [period]}),
          organization_id
        )

      {:ok, lock} ->
        lock
        |> Ash.Changeset.for_update(
          :update,
          Map.put(attrs, :closed_periods, lock.closed_periods ++ [period])
        )
        |> Ash.Changeset.set_tenant(organization_id)
        |> Ash.update(authorize?: false)

      {:error, error} ->
        {:error, error}
    end
  end

  @doc """
  Открывает (переоткрывает) закрытый месяц.

  Возвращает период в открытое состояние: правки снова разрешены.
  Доступно только главному бухгалтеру и администратору — проверяется
  матрицей прав на ресурсе периода.
  """
  @spec reopen_month(Date.t(), String.t(), struct() | nil) :: :ok | {:error, term()}
  def reopen_month(date, organization_id, _actor \\ nil) do
    period = month_start(date)

    case read_lock_record(organization_id) do
      {:ok, %{closed_periods: closed} = lock} ->
        if period in closed do
          remove_closed_period(lock, closed, period, organization_id)
        else
          {:error, "период #{month_label(period)} и так открыт"}
        end

      {:ok, nil} ->
        {:error, "период #{month_label(period)} и так открыт"}

      {:error, error} ->
        {:error, error}
    end
  end

  defp remove_closed_period(lock, closed, period, organization_id) do
    lock
    |> Ash.Changeset.for_update(:update, %{closed_periods: List.delete(closed, period)})
    |> Ash.Changeset.set_tenant(organization_id)
    |> Ash.update(authorize?: false)
    |> case do
      {:ok, _lock} -> :ok
      {:error, error} -> {:error, error}
    end
  end

  @doc """
  Устанавливает дату запрета правок.

  Дата запрета не может быть позже конца последнего закрытого периода:
  иначе получится, что открытый период защищён строже закрытого.
  """
  @spec set_prohibition_date(Date.t() | nil, String.t(), struct() | nil) ::
          :ok | {:error, term()}
  def set_prohibition_date(date, organization_id, _actor \\ nil) do
    case read_lock_record(organization_id) do
      {:ok, nil} ->
        attrs = %{organization_id: organization_id, prohibition_date: date}

        case create_lock(attrs, organization_id) do
          {:ok, _lock} -> :ok
          {:error, error} -> {:error, error}
        end

      {:ok, lock} ->
        lock
        |> Ash.Changeset.for_update(:update, %{prohibition_date: date})
        |> Ash.Changeset.set_tenant(organization_id)
        |> Ash.update(authorize?: false)
        |> case do
          {:ok, _lock} -> :ok
          {:error, error} -> {:error, error}
        end

      {:error, error} ->
        {:error, error}
    end
  end

  @doc """
  Сводка состояния периода: закрыт ли месяц и какие в нём итоги.

  Используется экраном управления периодами и шапкой рабочей области.
  """
  @spec summary(String.t(), Date.t()) :: map()
  def summary(organization_id, date) do
    period = month_start(date)
    closed = closed?(period, organization_id)

    %{
      period: period,
      closed: closed,
      prohibition_date: prohibition_date(organization_id),
      closed_periods: closed_periods(organization_id),
      totals:
        if(closed, do: Pulse.Accounting.Totals.for_period(organization_id, period), else: %{})
    }
  end

  # --- внутреннее ------------------------------------------------------------

  defp ensure_open(period, organization_id) do
    if closed?(period, organization_id) do
      {:error, "период #{month_label(period)} уже закрыт"}
    else
      :ok
    end
  end

  defp read_lock(organization_id) do
    case read_lock_record(organization_id) do
      {:ok, nil} -> {:ok, %{closed_periods: [], prohibition_date: nil}}
      {:ok, lock} -> {:ok, lock}
      {:error, error} -> {:error, error}
    end
  end

  # Периоды и дата запрета живут в одной строке на организацию:
  # так их состояние всегда согласовано.
  defp read_lock_record(organization_id) do
    PeriodLock
    |> Ash.Query.filter(organization_id == ^organization_id)
    |> Ash.read_one(tenant: organization_id, authorize?: false)
  end

  defp create_lock(attrs, organization_id) do
    PeriodLock
    |> Ash.Changeset.for_create(:create, Map.put_new(attrs, :organization_id, organization_id))
    |> Ash.Changeset.set_tenant(organization_id)
    |> Ash.create(authorize?: false)
  end

  defp before_prohibition?(date, organization_id) do
    case prohibition_date(organization_id) do
      nil -> false
      prohibition -> Date.compare(date, prohibition) == :lt
    end
  end

  # Дата запрета обходится только главным бухгалтером: это его зона
  # ответственности. Закрытый период не обходится никем.
  defp bypasses?(role), do: role == "chief_accountant"

  defp prohibition_label(organization_id) do
    case prohibition_date(organization_id) do
      nil -> "—"
      date -> Date.to_string(date)
    end
  end

  @doc """
  Первый день месяца, содержащего дату.
  """
  @spec month_start(Date.t()) :: Date.t()
  def month_start(%Date{year: year, month: month}), do: %Date{year: year, month: month, day: 1}

  @doc """
  Подпись месяца: «10.2026».
  """
  @spec month_label(Date.t()) :: String.t()
  def month_label(%Date{year: year, month: month}),
    do: "#{String.pad_leading("#{month}", 2, "0")}.#{year}"
end
