defmodule PulseWeb.Components.DocumentComponent do
  @moduledoc """
  Форма документа с табличной частью.

  Показывает реальные данные: реквизиты, строки и — у проведённого
  документа — движения, которые сформировало проведение. Проведение
  и отмена выполняются в LiveView (`Pulse.Accounting.Posting`).
  """
  use PulseWeb, :html

  alias PulseWeb.Components.StatusPill

  attr :spec, :map, required: true
  attr :document, :any, required: true
  attr :movements, :list, default: []

  def document(assigns) do
    assigns =
      assigns
      |> assign(:lines, lines(assigns.document))
      |> assign(:total, total(lines(assigns.document)))

    ~H"""
    <h1>
      {@spec.title} {if @document.number, do: "№ #{@document.number}"}
      <StatusPill.status_pill status={@document.status} />
    </h1>
    <p class="sub">
      Документ от {format_date(@document.doc_date)}
      <%= if @document.posted_at do %>
        · проведён {format_datetime(@document.posted_at)}
      <% end %>
    </p>

    <div class="tool">
      <button
        :if={@document.status == :draft}
        class="btn p"
        id="post-document"
        phx-click="save-document"
      >
        Провести
      </button>
      <button
        :if={@document.status == :posted}
        class="btn"
        id="unpost-document"
        phx-click="unpost-document"
      >
        Отменить проведение
      </button>
      <button class="btn" id="close-document" phx-click="close-document">Закрыть</button>
    </div>

    <div class="fm">
      <div>
        <label>Организация</label>
        <input class="f" value={@document.organization_id} readonly />
      </div>
      <div>
        <label>Дата</label>
        <input class="f" type="date" value={Date.to_string(@document.doc_date)} readonly />
      </div>
      <div>
        <label>Номер</label>
        <input class="f" value={@document.number || "—"} readonly />
      </div>
      <div>
        <label>Курс</label>
        <input class="f" value={Decimal.to_string(@document.rate || Decimal.new(1))} readonly />
      </div>
    </div>

    <div class="tw">
      <table id="document-lines">
        <thead>
          <tr>
            <th>№</th>
            <th>Номенклатура</th>
            <th class="n">Кол-во</th>
            <th class="n">Цена</th>
            <th class="n">Сумма</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={line <- @lines} id={"document-line-#{line.id}"}>
            <td>{line.line_no}</td>
            <td>{line.nomenclature_id}</td>
            <td class="n">{decimal(line.quantity)}</td>
            <td class="n">{decimal(line.price)}</td>
            <td class="n">{decimal(line_amount(line))}</td>
          </tr>
          <tr :if={@lines == []}>
            <td colspan="5" class="empty">В документе нет строк</td>
          </tr>
        </tbody>
      </table>
    </div>

    <div class="tool" style="margin-top: 12px">
      <div class="sp"></div>
      <div class="n">
        <b style="font-size: 18px">Итого: {decimal(@total)}</b>
      </div>
    </div>

    <div :if={@movements != []} class="cd" style="margin-top: 18px">
      <h2>Движения ТМЗ</h2>
      <table id="document-movements">
        <thead>
          <tr>
            <th>Вид</th>
            <th>Номенклатура</th>
            <th class="n">Количество</th>
            <th class="n">Стоимость</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={movement <- @movements} id={"movement-#{movement.id}"}>
            <td>{movement_label(movement.record_type)}</td>
            <td>{movement.nomenclature_id}</td>
            <td class="n">{decimal(movement.quantity)}</td>
            <td class="n">{decimal(movement.cost)}</td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  defp lines(%{lines: %Ash.NotLoaded{}}), do: []
  defp lines(%{lines: lines}), do: lines
  defp lines(_document), do: []

  defp line_amount(line), do: line.amount || Decimal.mult(line.quantity, line.price)

  defp total(lines) do
    Enum.reduce(lines, Decimal.new(0), fn line, acc -> Decimal.add(acc, line_amount(line)) end)
  end

  defp movement_label(:receipt), do: "Приход"
  defp movement_label(:expense), do: "Расход"

  defp decimal(nil), do: "—"

  defp decimal(value) do
    value
    |> Decimal.round(2)
    |> Decimal.to_string()
  end

  defp format_date(nil), do: "—"
  defp format_date(%Date{} = date), do: Date.to_string(date)

  defp format_datetime(%DateTime{} = datetime) do
    datetime
    |> DateTime.truncate(:second)
    |> DateTime.to_string()
  end
end
