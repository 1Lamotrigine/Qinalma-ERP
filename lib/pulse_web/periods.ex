defmodule PulseWeb.Periods do
  @moduledoc """
  Экран управления периодами: закрытие месяца и дата запрета правок.

  Доступен по пунктам меню «Помощник «Закрытие месяца»» и «Даты запрета
  изменения данных». Менять состояние может только главный бухгалтер
  и администратор — это проверяет политика ресурса периода.
  """

  alias Pulse.Accounting.Periods

  @doc """
  Заголовки меню, которые открывают экран периодов.
  """
  @spec titles() :: [String.t()]
  def titles do
    ["Помощник «Закрытие месяца»", "Даты запрета изменения данных", "Закрытия месяца"]
  end

  @doc """
  Открывает ли заголовок экран периодов.
  """
  @spec screen?(String.t()) :: boolean()
  def screen?(title), do: title in titles()

  @doc """
  Состояние периодов организации для экрана.
  """
  @spec state(String.t(), Date.t()) :: map()
  def state(organization_id, date) do
    summary = Periods.summary(organization_id, date)

    Map.merge(summary, %{
      current: Periods.month_start(date),
      next_closed: next_closed(organization_id)
    })
  end

  @doc """
  Закрывает месяц, содержащий дату.
  """
  @spec close_month(Date.t(), String.t(), struct()) :: {:ok, map()} | {:error, String.t()}
  def close_month(date, organization_id, actor) do
    case Periods.close_month(date, organization_id, actor) do
      {:ok, result} -> {:ok, result}
      {:error, error} -> {:error, error_message(error)}
    end
  end

  @doc """
  Открывает месяц обратно.
  """
  @spec reopen_month(Date.t(), String.t(), struct()) :: :ok | {:error, String.t()}
  def reopen_month(date, organization_id, actor) do
    case Periods.reopen_month(date, organization_id, actor) do
      :ok -> :ok
      {:error, error} -> {:error, error_message(error)}
    end
  end

  @doc """
  Устанавливает дату запрета правок.
  """
  @spec set_prohibition_date(Date.t() | nil, String.t(), struct()) :: :ok | {:error, String.t()}
  def set_prohibition_date(date, organization_id, actor) do
    case Periods.set_prohibition_date(date, organization_id, actor) do
      :ok -> :ok
      {:error, error} -> {:error, error_message(error)}
    end
  end

  # Следующий месяц после последнего закрытого — то, что логично
  # предложить к закрытию.
  defp next_closed(organization_id) do
    case Periods.closed_periods(organization_id) do
      [] -> nil
      [latest | _rest] -> shift_month(latest, 1)
    end
  end

  defp shift_month(%Date{year: year, month: month}, offset) do
    total = year * 12 + (month - 1) + offset
    %Date{year: div(total, 12), month: rem(total, 12) + 1, day: 1}
  end

  defp error_message(error) when is_binary(error), do: error
  defp error_message(error), do: Exception.message(error)
end
