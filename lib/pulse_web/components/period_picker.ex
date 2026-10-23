defmodule PulseWeb.Components.PeriodPicker do
  @moduledoc """
  Выбор периода: с какой по какую дату.

  Значения — `Date`. Обработчик задаётся вызывающим компонентом.
  """
  use PulseWeb, :html

  attr :from, :any, default: nil
  attr :to, :any, default: nil
  attr :id, :string, default: "period"
  attr :target, :any, default: nil
  attr :change_event, :string, default: "change-period"

  def period_picker(assigns) do
    ~H"""
    <label>
      Период:
      <input
        class="f"
        type="date"
        id={"#{@id}-from"}
        name="from"
        value={format_date(@from)}
        phx-change={@change_event}
        phx-target={@target}
      /> —
      <input
        class="f"
        type="date"
        id={"#{@id}-to"}
        name="to"
        value={format_date(@to)}
        phx-change={@change_event}
        phx-target={@target}
      />
    </label>
    """
  end

  defp format_date(%Date{} = date), do: Date.to_iso8601(date)
  defp format_date(_), do: ""
end
