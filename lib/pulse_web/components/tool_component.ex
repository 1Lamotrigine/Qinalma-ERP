defmodule PulseWeb.Components.ToolComponent do
  @moduledoc """
  Обработка или настройка: простая карточка с кнопкой действия.

  Конкретные обработки подключаются на своих этапах.
  """
  use PulseWeb, :html

  attr :title, :string, required: true
  attr :section, :map, required: true
  attr :group, :string, required: true

  def tool(assigns) do
    ~H"""
    <h1>{@title}</h1>
    <p class="sub">{@section.title} · {@group}</p>

    <div class="cd" style="max-width: 560px">
      <p>Здесь будет форма обработки или настройки. Подключите свою логику к кнопке.</p>
      <button class="btn p" phx-click="toast" phx-value-message="Выполнено">Выполнить</button>
    </div>
    """
  end
end
