defmodule PulseWeb.Components.Tabs do
  @moduledoc """
  Полоса вкладок рабочей области.

  Каждая вкладка — кнопка с обработчиками `switch-tab` и `close-tab`.
  """
  use PulseWeb, :html

  attr :tabs, :list, required: true
  attr :active_id, :string, default: nil
  attr :hub_active, :boolean, default: false

  def tabs(assigns) do
    ~H"""
    <div class="ws-tabs" id="ws-tabs">
      <button
        :for={tab <- @tabs}
        type="button"
        class={["tb", !@hub_active && @active_id == tab.id && "on"]}
        phx-click="switch-tab"
        phx-value-id={tab.id}
      >
        <span :if={tab[:home]}>⌂</span>
        <span>{tab.title}</span>
        <span
          :if={!tab[:home]}
          class="x"
          phx-click="close-tab"
          phx-value-id={tab.id}
          title="Закрыть вкладку"
        >
          ✕
        </span>
      </button>
    </div>
    """
  end
end
