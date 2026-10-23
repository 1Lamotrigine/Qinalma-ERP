defmodule Pulse.Workers.RecalculateMonth do
  @moduledoc """
  Задача Oban: пересчёт себестоимости месяца.

  Ставится в очередь после проведения документа задним числом: расходы
  последующих документов месяца считались по старой средней
  себестоимости и требуют переоценки.
  """
  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger

  @doc """
  Ставит пересчёт месяца в очередь.
  """
  @spec enqueue(Date.t(), String.t()) :: {:ok, Oban.Job.t()} | {:error, term()}
  def enqueue(date, organization_id) do
    if Pulse.Application.oban_disabled?() do
      {:error, :oban_disabled}
    else
      %{date: Date.to_iso8601(date), organization_id: organization_id}
      |> new()
      |> Oban.insert()
    end
  end

  @impl true
  def perform(%Oban.Job{args: args}) do
    date = Date.from_iso8601!(args["date"])
    organization_id = args["organization_id"]

    case Pulse.Accounting.Recalculation.recalculate_month(organization_id, date) do
      {:ok, %{updated: updated}} ->
        Logger.info("Пересчёт себестоимости: обновлено движений — #{updated}")
        :ok

      {:error, reason} ->
        Logger.error("Не удалось пересчитать себестоимость: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
