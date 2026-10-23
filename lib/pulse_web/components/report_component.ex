defmodule PulseWeb.Components.ReportComponent do
  @moduledoc """
  Бухгалтерский отчёт: панель параметров и область результата.

  Колонки и строки приходят из реестра отчётов (`PulseWeb.Reports`):
  компонент не знает, какой отчёт показывает — ОСВ, карточку, анализ
  или главную книгу.
  """
  use PulseWeb, :html

  attr :title, :string, required: true
  attr :section, :map, required: true
  attr :result, :any, default: nil
  attr :params, :map, default: %{}
  attr :account?, :boolean, default: false
  attr :counterparty?, :boolean, default: false
  attr :counterparties, :list, default: []
  attr :employee?, :boolean, default: false
  attr :employees, :list, default: []

  def report(assigns) do
    ~H"""
    <h1>{@title}</h1>
    <p class="sub">{@section.title} · отчет</p>

    <div class="tool">
      <label>
        Период:
        <input
          class="f"
          id="report-from"
          type="date"
          value={@params["from"]}
          phx-change="report-period"
        /> —
        <input
          class="f"
          id="report-to"
          type="date"
          value={@params["to"]}
          phx-change="report-period"
        />
      </label>

      <label :if={@account?}>
        Счет:
        <input
          class="f"
          id="report-account"
          style="width: 90px"
          value={@params["account"]}
          phx-change="report-period"
        />
      </label>

      <label :if={@counterparty?}>
        Контрагент:
        <select class="f" id="report-counterparty" phx-change="report-period">
          <option value="">— выберите —</option>
          <option
            :for={{value, label} <- @counterparties}
            value={value}
            selected={value == @params["counterparty"]}
          >
            {label}
          </option>
        </select>
      </label>

      <label :if={@employee?}>
        Сотрудник:
        <select class="f" id="report-employee" phx-change="report-period">
          <option value="">— выберите —</option>
          <option
            :for={{value, label} <- @employees}
            value={value}
            selected={value == @params["employee"]}
          >
            {label}
          </option>
        </select>
      </label>

      <button class="btn p" id="report-build" phx-click="generate-report">Сформировать</button>
    </div>

    <div class="tw" id="report-result">
      <div :if={is_nil(@result)} class="empty">
        Задайте период и нажмите «Сформировать»
      </div>

      <%= if @result do %>
        <p :if={@result[:headline]} class="sub">{@result.headline}</p>

        <table>
          <thead>
            <tr>
              <th :for={column <- @result.columns}>{column}</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={row <- @result.rows}>
              <td :for={cell <- row}>{cell}</td>
            </tr>
            <tr :if={@result.rows == []}>
              <td colspan={length(@result.columns)} class="empty">Нет данных за период</td>
            </tr>
          </tbody>
          <tfoot :if={@result.totals != []}>
            <tr>
              <td :for={cell <- @result.totals}><b>{cell}</b></td>
            </tr>
          </tfoot>
        </table>
      <% end %>
    </div>
    """
  end
end
