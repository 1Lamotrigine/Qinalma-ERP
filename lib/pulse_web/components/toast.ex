defmodule PulseWeb.Components.Toast do
  @moduledoc """
  Всплывающее уведомление внизу экрана.

  Управляется присвоением `:toast` в LiveView: строка или `nil`.
  Показывается на 2,2 секунды, затем скрывается событием `clear-toast`.
  """
  use PulseWeb, :html

  attr :toast, :string, default: nil

  def toast(assigns) do
    ~H"""
    <div id="toast" class={["toast", @toast && "on"]} aria-live="polite">
      {@toast}
    </div>
    """
  end
end
