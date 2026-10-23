defmodule Pulse.Tax.Esf do
  @moduledoc """
  Выгрузка счёта-фактуры в XML (раздел 5.5 ТЗ).

  Формируется структура данных счёта-фактуры по формату ИС ЭСФ:
  реквизиты продавца и покупателя, строки, суммы НДС. Сама интеграция
  с ИС ЭСФ требует ЭЦП и отдельного тестового контура — здесь только
  подготовка данных и выгрузка.

  XML собирается без внешних зависимостей: структура невелика,
  а лишняя библиотека в поставке ни к чему.
  """

  alias Pulse.Tax.Invoice

  @doc """
  Данные счёта-фактуры для выгрузки.

  Возвращает карту с реквизитами сторон и суммами — её же использует
  печатная форма.
  """
  @spec data(Invoice.t(), struct() | nil, struct() | nil) :: map()
  def data(invoice, seller \\ nil, buyer \\ nil) do
    %{
      number: invoice.number,
      invoice_date: invoice.invoice_date,
      direction: invoice.direction,
      seller: party(seller),
      buyer: party(buyer),
      amount: invoice.amount,
      vat_rate: invoice.vat_rate,
      vat_amount: invoice.vat_amount || Decimal.new(0),
      net_amount: Invoice.net_amount(invoice.amount, invoice.vat_rate)
    }
  end

  @doc """
  XML счёта-фактуры.

  Кодировка — UTF-8, объявление и корневой элемент соответствуют
  структуре выгрузки для ИС ЭСФ.
  """
  @spec to_xml(Invoice.t(), struct() | nil, struct() | nil) :: String.t()
  def to_xml(invoice, seller \\ nil, buyer \\ nil) do
    data = data(invoice, seller, buyer)

    [
      ~s(<?xml version="1.0" encoding="UTF-8"?>\n),
      "<invoice>\n",
      "  <header>\n",
      "    <number>#{escape(data.number)}</number>\n",
      "    <date>#{Date.to_string(data.invoice_date)}</date>\n",
      "    <direction>#{data.direction}</direction>\n",
      "  </header>\n",
      party_xml("seller", data.seller),
      party_xml("buyer", data.buyer),
      "  <totals>\n",
      "    <netAmount>#{money(data.net_amount)}</netAmount>\n",
      "    <vatRate>#{money(data.vat_rate)}</vatRate>\n",
      "    <vatAmount>#{money(data.vat_amount)}</vatAmount>\n",
      "    <grossAmount>#{money(data.amount)}</grossAmount>\n",
      "  </totals>\n",
      "</invoice>\n"
    ]
    |> IO.iodata_to_binary()
  end

  @doc """
  Имя файла выгрузки.
  """
  @spec filename(Invoice.t()) :: String.t()
  def filename(invoice) do
    safe = invoice.number |> to_string() |> String.replace(~r/[^\w\-.]/u, "_")
    "#{safe}_#{Date.to_string(invoice.invoice_date)}.xml"
  end

  defp party(nil), do: %{name: nil, bin: nil, address: nil}

  defp party(organization) do
    %{
      name: Map.get(organization, :name),
      bin: Map.get(organization, :bin) || Map.get(organization, :iin),
      address: Map.get(organization, :address)
    }
  end

  defp party_xml(tag, party) do
    [
      "  <#{tag}>\n",
      "    <name>#{escape(party.name)}</name>\n",
      "    <bin>#{escape(party.bin)}</bin>\n",
      "    <address>#{escape(party.address)}</address>\n",
      "  </#{tag}>\n"
    ]
  end

  defp money(nil), do: "0"

  defp money(value) do
    value
    |> Decimal.round(2)
    |> Decimal.to_string()
  end

  defp escape(nil), do: ""

  defp escape(value) do
    value
    |> to_string()
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace(~s("), "&quot;")
  end
end
