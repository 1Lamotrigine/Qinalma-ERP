defmodule PulseWeb.Tax do
  @moduledoc """
  Реестр налогового контура рабочей области (этап 7).

  Счета-фактуры не вводятся руками: они формируются по проведённым
  документам (`Pulse.Tax.Invoices`). Поэтому журнал счетов-фактур —
  только чтение: строки журнала ведут в печатную форму и выгрузку XML,
  но не создают новые записи.

  Ставки налогов и пороги живут в справочнике `Pulse.Tax.StatutoryRate`
  и правятся через `PulseWeb.Catalogs`.
  """

  alias Pulse.Tax.Invoice
  alias Pulse.Tax.Invoices
  require Ash.Query

  @doc """
  Спецификация журнала счетов-фактур по заголовку пункта меню.
  """
  @spec spec(String.t()) :: map() | nil
  def spec("Счета-фактуры (выданные)"), do: invoice_spec(:issued)
  def spec("Счета-фактуры (полученные)"), do: invoice_spec(:received)
  def spec(_title), do: nil

  @doc """
  Загружает счета-фактуры для журнала.
  """
  @spec list(map(), struct()) :: {:ok, [map()]} | {:error, String.t()}
  def list(spec, actor) do
    if is_nil(actor.organization_id) do
      {:ok, []}
    else
      Invoice
      |> Ash.Query.filter(direction == ^spec.direction)
      |> Ash.Query.sort(invoice_date: :desc, inserted_at: :desc)
      |> Ash.Query.load([:counterparty])
      |> Ash.read(tenant: actor.organization_id, authorize?: false)
      |> case do
        {:ok, invoices} -> {:ok, Enum.map(invoices, &row/1)}
        # Политика запретила — в журнале пусто, а не ошибка экрана.
        {:error, %Ash.Error.Forbidden{}} -> {:ok, []}
        {:error, error} -> {:error, Exception.message(error)}
      end
    end
  end

  @doc """
  Итоги по журналу: суммы с НДС, без НДС и НДС.
  """
  @spec totals(map(), struct()) :: map()
  def totals(spec, actor) do
    if is_nil(actor.organization_id) do
      %{gross: Decimal.new(0), vat: Decimal.new(0), net: Decimal.new(0)}
    else
      Invoice
      |> Ash.Query.filter(direction == ^spec.direction)
      |> Ash.read(tenant: actor.organization_id, authorize?: false)
      |> case do
        {:ok, invoices} -> Invoices.totals(invoices)
        _ -> %{gross: Decimal.new(0), vat: Decimal.new(0), net: Decimal.new(0)}
      end
    end
  end

  defp invoice_spec(direction) do
    %{
      title: direction_title(direction),
      direction: direction,
      columns: [
        %{key: :number, label: "Номер"},
        %{key: :invoice_date, label: "Дата"},
        %{key: :counterparty_name, label: "Контрагент"},
        %{key: :net_amount, label: "Без НДС", align: :right},
        %{key: :vat_rate, label: "НДС, %", align: :right},
        %{key: :vat_amount, label: "НДС", align: :right},
        %{key: :amount, label: "С НДС", align: :right}
      ]
    }
  end

  defp direction_title(:issued), do: "Счета-фактуры (выданные)"
  defp direction_title(:received), do: "Счета-фактуры (полученные)"

  defp row(invoice) do
    %{
      id: invoice.id,
      number: invoice.number,
      invoice_date: Date.to_string(invoice.invoice_date),
      counterparty_name: counterparty_name(invoice),
      net_amount: money(Invoice.net_amount(invoice.amount, invoice.vat_rate)),
      vat_rate: money(invoice.vat_rate),
      vat_amount: money(invoice.vat_amount || Decimal.new(0)),
      amount: money(invoice.amount)
    }
  end

  defp counterparty_name(%{counterparty: %Ash.NotLoaded{}}), do: nil
  defp counterparty_name(%{counterparty: nil}), do: nil
  defp counterparty_name(%{counterparty: %{name: name}}), do: name
  defp counterparty_name(_invoice), do: nil

  defp money(nil), do: nil

  defp money(value) do
    value
    |> Decimal.round(2)
    |> Decimal.to_string()
  end
end
