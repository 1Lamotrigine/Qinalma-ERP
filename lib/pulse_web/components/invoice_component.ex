defmodule PulseWeb.Components.InvoiceComponent do
  @moduledoc """
  Печатная форма счёта-фактуры (этап 7).

  Показывает реквизиты сторон и суммы, а также данные, подготовленные
  к выгрузке в XML (`Pulse.Tax.Esf`). Счёт-фактура формируется по
  документу-основанию, поэтому форма доступна только для чтения.
  """
  use PulseWeb, :html

  attr :invoice, :any, required: true
  attr :data, :map, required: true
  attr :xml, :string, required: true

  def invoice(assigns) do
    ~H"""
    <h1>
      {direction_title(@invoice.direction)} № {@invoice.number}
    </h1>
    <p class="sub">
      Счёт-фактура от {Date.to_string(@invoice.invoice_date)} · сформирован по документу-основанию
    </p>

    <div class="tool">
      <a
        class="btn p"
        id="download-invoice-xml"
        href={~p"/invoices/#{@invoice.id}/xml"}
        download
      >
        Выгрузить XML
      </a>
      <button class="btn" id="close-invoice" phx-click="close-document">Закрыть</button>
    </div>

    <div class="fm">
      <div>
        <label>Продавец</label>
        <input class="f" value={@data.seller.name || "—"} readonly />
      </div>
      <div>
        <label>БИН/ИИН продавца</label>
        <input class="f" value={@data.seller.bin || "—"} readonly />
      </div>
      <div>
        <label>Покупатель</label>
        <input class="f" value={@data.buyer.name || "—"} readonly />
      </div>
      <div>
        <label>БИН/ИИН покупателя</label>
        <input class="f" value={@data.buyer.bin || "—"} readonly />
      </div>
    </div>

    <div class="tw" style="margin-top: 12px">
      <table id="invoice-totals">
        <thead>
          <tr>
            <th class="n">Сумма без НДС</th>
            <th class="n">Ставка НДС, %</th>
            <th class="n">Сумма НДС</th>
            <th class="n">Сумма с НДС</th>
          </tr>
        </thead>
        <tbody>
          <tr>
            <td class="n">{money(@data.net_amount)}</td>
            <td class="n">{money(@data.vat_rate)}</td>
            <td class="n">{money(@data.vat_amount)}</td>
            <td class="n">{money(@data.amount)}</td>
          </tr>
        </tbody>
      </table>
    </div>

    <div class="cd" style="margin-top: 18px">
      <h2>Выгрузка XML</h2>
      <pre id="invoice-xml" phx-no-curly-interpolation style="white-space: pre-wrap">{@xml}</pre>
    </div>
    """
  end

  defp money(nil), do: "—"

  defp money(value) do
    value
    |> Decimal.round(2)
    |> Decimal.to_string()
  end

  defp direction_title(:issued), do: "Счёт-фактура выданная"
  defp direction_title(:received), do: "Счёт-фактура полученная"
  defp direction_title(_direction), do: "Счёт-фактура"
end
