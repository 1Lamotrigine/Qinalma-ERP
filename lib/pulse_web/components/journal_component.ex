defmodule PulseWeb.Components.JournalComponent do
  @moduledoc """
  Журнал документов или справочника.

  Источник данных и колонки приходят из LiveView: для справочников —
  реальные записи Ash (`PulseWeb.Catalogs`), для документов этапа 3 —
  демонстрационные строки. Компонент задаёт структуру — панель
  инструментов, таблица, фильтры.
  """
  use PulseWeb, :html

  alias PulseWeb.Components.DataGrid

  attr :section, :map, required: true
  attr :group, :string, required: true
  attr :title, :string, required: true
  attr :kind, :atom, required: true
  attr :rows, :list, required: true
  attr :filter, :string, default: ""

  # Колонки берутся из реестра справочников; пустой список — «по умолчанию».
  attr :columns, :list, default: []

  # Журнал показывает реальные документы: подсказка о проведении уместна.
  attr :document?, :boolean, default: false

  def journal(assigns) do
    assigns =
      assign(assigns,
        columns: journal_columns(assigns.columns, assigns.kind),
        filtered_rows: filter_rows(assigns.rows, assigns.filter)
      )

    ~H"""
    <h1>{@title}</h1>
    <p class="sub">{@section.title} · {@group}</p>

    <div class="tool">
      <button class="btn p" phx-click="create-document" phx-value-title={@title}>
        Создать
      </button>
      <button
        :if={@kind != :catalog}
        class="btn"
        phx-click="toast"
        phx-value-message="Документ проведён"
      >
        Провести
      </button>
      <button
        :if={@kind != :catalog}
        class="btn"
        phx-click="toast"
        phx-value-message="Печатная форма сформирована"
      >
        Печать
      </button>
      <input
        class="f"
        id="journal-filter"
        placeholder="Поиск (Ctrl+F)"
        style="width: 240px"
        value={@filter}
        phx-keyup="filter-journal"
        phx-debounce="120"
      />
    </div>

    <DataGrid.data_grid
      id="journal-grid"
      columns={@columns}
      rows={@filtered_rows}
      empty_text="Ничего не найдено"
      row_click_event="open-document"
    />

    <div :if={@document?} class="tool" style="margin-top: 10px">
      <span class="sub">
        Документы проводятся из формы: откройте строку журнала.
      </span>
    </div>
    """
  end

  defp journal_columns([], kind), do: columns(kind)
  defp journal_columns(columns, _kind), do: columns

  defp columns(:catalog) do
    [
      %{key: :who, label: "Наименование"},
      %{key: :no, label: "Код"},
      %{key: :comment, label: "Комментарий"}
    ]
  end

  defp columns(_) do
    [
      %{key: :date, label: "Дата"},
      %{key: :no, label: "Номер"},
      %{key: :who, label: "Контрагент"},
      %{key: :wh, label: "Склад"},
      %{key: :sum, label: "Сумма, KZT", align: :right, format: &format_sum/1},
      %{key: :status, label: "Состояние", format: &format_status/1}
    ]
  end

  defp filter_rows(rows, filter) do
    filter = String.downcase(String.trim(filter || ""))

    if filter == "" do
      rows
    else
      Enum.filter(rows, fn row ->
        row
        |> Map.values()
        |> Enum.any?(&String.contains?(String.downcase(to_string(&1)), filter))
      end)
    end
  end

  defp format_sum(row) do
    row.sum
    |> PulseWeb.Components.MoneyInput.format_money()
    |> Phoenix.HTML.raw()
  end

  defp format_status(row) do
    case row[:status] do
      :posted -> Phoenix.HTML.raw(~s(<span class="pill">Проведен</span>))
      _ -> Phoenix.HTML.raw(~s(<span class="pill w">Не проведен</span>))
    end
  end
end
