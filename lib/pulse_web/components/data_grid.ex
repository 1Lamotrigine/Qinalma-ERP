defmodule PulseWeb.Components.DataGrid do
  @moduledoc """
  Таблица данных с keyset-пагинацией.

  Колонки описываются списком: `%{key: :date, label: "Дата", align: :left, format: fun}`
  либо просто `%{key: :title, label: "Наименование"}`.

  Строки — список карт или структур. Значение колонки берётся по ключу.

  Пагинация keyset: страница задаётся курсором, а не номером. Компонент
  лишь рисует кнопки «Назад» и «Вперёд» и шлёт события `page-next` и
  `page-prev`, а загрузку данных делает LiveView.
  """
  use PulseWeb, :html

  attr :columns, :list, required: true
  attr :rows, :list, required: true
  attr :id, :string, required: true
  attr :empty_text, :string, default: "Ничего не найдено"
  attr :row_click_event, :string, default: nil
  attr :row_id_fun, :any, default: nil
  attr :has_prev, :boolean, default: false
  attr :has_next, :boolean, default: false

  def data_grid(assigns) do
    ~H"""
    <div class="tw">
      <table id={@id}>
        <thead>
          <tr>
            <th :for={col <- @columns} class={col_align_class(col)}>{col.label}</th>
          </tr>
        </thead>
        <tbody>
          <tr :if={@rows == []}>
            <td colspan={length(@columns)} class="empty">{@empty_text}</td>
          </tr>
          <tr
            :for={row <- @rows}
            id={row_id(assigns, row)}
            phx-click={@row_click_event}
            phx-value-id={row_value(row, :id)}
            class={@row_click_event && "cursor-pointer"}
          >
            <td :for={col <- @columns} class={col_align_class(col)}>
              {cell_value(row, col)}
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <div :if={@has_prev || @has_next} class="tool" style="margin-top: 12px">
      <button :if={@has_prev} class="btn" phx-click="page-prev">← Назад</button>
      <div class="sp"></div>
      <button :if={@has_next} class="btn" phx-click="page-next">Вперёд →</button>
    </div>
    """
  end

  defp col_align_class(%{align: :right}), do: "n"
  defp col_align_class(_), do: nil

  defp row_id(%{row_id_fun: nil}, row), do: "row-#{row_value(row, :id)}"
  defp row_id(assigns, row), do: assigns.row_id_fun.(row)

  defp cell_value(row, %{format: fun}), do: fun.(row)
  defp cell_value(row, %{key: key}), do: row_value(row, key)

  defp row_value(row, key) when is_map(row), do: Map.get(row, key)
  defp row_value(_row, _key), do: nil
end
