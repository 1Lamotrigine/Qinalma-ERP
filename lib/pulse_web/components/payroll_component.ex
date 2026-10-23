defmodule PulseWeb.Components.PayrollComponent do
  @moduledoc """
  Расчётная ведомость: строки по сотрудникам и итоги.

  Показывает начисление, удержания и суммы к выплате. Проведение и
  отмена — те же кнопки, что у прочих документов.
  """
  use PulseWeb, :html

  alias PulseWeb.Components.StatusPill

  attr :document, :any, required: true

  def accrual(assigns) do
    assigns =
      assigns
      |> assign(:lines, lines(assigns.document))
      |> assign(:totals, Pulse.Posting.PayrollAccrual.totals(assigns.document))

    ~H"""
    <h1>
      Начисление заработной платы № {@document.number}
      <StatusPill.status_pill status={@document.status} />
    </h1>
    <p class="sub">
      Документ от {format_date(@document.doc_date)}
      <%= if @document.period do %>
        · за {format_period(@document.period)}
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

    <div class="tw">
      <table id="document-lines">
        <thead>
          <tr>
            <th>№</th>
            <th>Сотрудник</th>
            <th class="n">Начислено</th>
            <th class="n">ОПВ</th>
            <th class="n">ВОСМС</th>
            <th class="n">ИПН</th>
            <th class="n">К выплате</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={line <- @lines} id={"document-line-#{line.id}"}>
            <td>{line.line_no}</td>
            <td>{employee_name(line)}</td>
            <td class="n">{decimal(line.gross)}</td>
            <td class="n">{decimal(line.opv)}</td>
            <td class="n">{decimal(line.vosms)}</td>
            <td class="n">{decimal(line.ipn)}</td>
            <td class="n">{decimal(line.net)}</td>
          </tr>
          <tr :if={@lines == []}>
            <td colspan="7" class="empty">В ведомости нет сотрудников</td>
          </tr>
        </tbody>
      </table>
    </div>

    <div class="tool" style="margin-top: 12px">
      <div class="sp"></div>
      <div class="n">
        <b style="font-size: 18px">Начислено: {decimal(@totals.gross)} · к выплате: {decimal(
          @totals.net
        )}</b>
      </div>
    </div>
    """
  end

  defp lines(%{lines: %Ash.NotLoaded{}}), do: []
  defp lines(%{lines: lines}), do: lines
  defp lines(_document), do: []

  defp employee_name(%{employee: %Ash.NotLoaded{}}), do: "—"
  defp employee_name(%{employee: nil}), do: "—"
  defp employee_name(%{employee: %{person: %Ash.NotLoaded{}}} = line), do: line.employee.id
  defp employee_name(%{employee: %{person: nil}} = line), do: line.employee.id
  defp employee_name(%{employee: %{person: person}}), do: Pulse.HR.Person.full_name(person)
  defp employee_name(_line), do: "—"

  defp decimal(nil), do: "—"

  defp decimal(value) do
    value
    |> Decimal.round(2)
    |> Decimal.to_string()
  end

  defp format_date(%Date{} = date), do: Date.to_string(date)
  defp format_date(nil), do: "—"

  defp format_period(%Date{} = date), do: "#{date.month}.#{date.year}"
  defp format_period(_date), do: "—"
end
