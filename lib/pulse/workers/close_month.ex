defmodule Pulse.Workers.CloseMonth do
  @moduledoc """
  Задача Oban: закрытие месяца (раздел 5.3 ТЗ).

  Закрытие — операция небыстрая: она пересчитывает себестоимость месяца
  целиком и собирает помесячные итоги. Поэтому она выполняется в фоне,
  а не в запросе пользователя.

  Задача идемпотентна: повторный запуск на закрытом месяце ничего
  не меняет и завершается успешно.
  """
  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger

  @doc """
  Ставит закрытие месяца в очередь.
  """
  @spec enqueue(Date.t(), String.t(), String.t() | nil) :: {:ok, Oban.Job.t()} | {:error, term()}
  def enqueue(date, organization_id, actor_id \\ nil) do
    %{date: Date.to_iso8601(date), organization_id: organization_id, actor_id: actor_id}
    |> new()
    |> Oban.insert()
  end

  @impl true
  def perform(%Oban.Job{args: args}) do
    date = Date.from_iso8601!(args["date"])
    organization_id = args["organization_id"]

    case Pulse.Accounting.Periods.close_month(date, organization_id, actor(args["actor_id"])) do
      {:ok, %{period: period}} ->
        Logger.info("Месяц #{Pulse.Accounting.Periods.month_label(period)} закрыт")
        :ok

      {:error, reason} ->
        Logger.error("Не удалось закрыть месяц: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Актор для аудита: достаточно идентификатора и роли — закрывать месяц
  # разрешено только главному бухгалтеру и администратору.
  defp actor(nil), do: nil

  defp actor(actor_id) do
    %Pulse.Core.Actor{id: actor_id, role: "chief_accountant"}
  end
end
