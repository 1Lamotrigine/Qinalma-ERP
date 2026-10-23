defmodule PulseWeb.Components.StatusPill do
  @moduledoc """
  Метка состояния документа: проведён, не проведён, отменён.
  """
  use PulseWeb, :html

  attr :status, :atom, required: true, values: [:draft, :posted, :cancelled]

  def status_pill(assigns) do
    assigns = assign(assigns, :label, label(assigns.status))

    ~H"""
    <span class={["pill", @status != :posted && "w"]}>{@label}</span>
    """
  end

  defp label(:draft), do: "Не проведен"
  defp label(:posted), do: "Проведен"
  defp label(:cancelled), do: "Отменен"
end
