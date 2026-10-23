defmodule Pulse.Tax.Invoices do
  @moduledoc """
  Формирование счетов-фактур из документов-оснований (раздел 5.5 ТЗ).

  Счёт-фактура не вводится руками: она строится по проведённому
  документу — реализации или поступлению. Ставка НДС берётся
  из законодательных параметров на дату документа
  (`Pulse.Tax.Rates`), поэтому смена ставки не требует релиза.

  Повторное формирование по тому же документу не создаёт дубль:
  возвращается уже существующий счёт-фактура.
  """
  require Ash.Query

  alias Pulse.Tax.Invoice
  alias Pulse.Tax.Rates

  @doc """
  Формирует счёт-фактуру по документу.

  `direction` — `:issued` для реализации, `:received` для поступления.
  Возвращает `{:ok, счёт-фактура}` либо `{:error, причина}`.
  """
  @spec create_from_document(struct(), :issued | :received) ::
          {:ok, Invoice.t()} | {:error, String.t()}
  def create_from_document(document, direction) do
    with nil <- existing(document),
         date <- document_date(document),
         {:ok, vat_rate} <- vat_rate(date) do
      amount = document_amount(document)

      attrs = %{
        direction: direction,
        number: number(document, direction),
        invoice_date: date,
        counterparty_id: Map.get(document, :counterparty_id),
        contract_id: Map.get(document, :contract_id),
        document_type: Pulse.Accounting.Posting.document_type(document),
        document_id: document.id,
        amount: amount,
        vat_rate: vat_rate,
        vat_amount: Invoice.vat_amount(amount, vat_rate),
        currency_id: Map.get(document, :currency_id)
      }

      Invoice
      |> Ash.Changeset.for_create(:create, attrs)
      |> Ash.Changeset.set_tenant(document.organization_id)
      |> Ash.create(authorize?: false)
    else
      %Invoice{} = invoice -> {:ok, invoice}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Существующий счёт-фактура по документу, если уже сформирован.
  """
  @spec existing(struct()) :: Invoice.t() | nil
  def existing(document) do
    type = Pulse.Accounting.Posting.document_type(document)

    Invoice
    |> Ash.Query.filter(document_type == ^type and document_id == ^document.id)
    |> Ash.read_one(tenant: document.organization_id, authorize?: false)
    |> case do
      {:ok, invoice} -> invoice
      _ -> nil
    end
  end

  @doc """
  Счета-фактуры организации по направлению за период.
  """
  @spec list(String.t(), :issued | :received, Date.t(), Date.t()) :: [Invoice.t()]
  def list(organization_id, direction, from, to) do
    Invoice
    |> Ash.Query.filter(direction == ^direction)
    |> Ash.Query.filter(invoice_date >= ^from and invoice_date <= ^to)
    |> Ash.Query.sort(invoice_date: :desc)
    |> Ash.read(tenant: organization_id, authorize?: false)
    |> case do
      {:ok, invoices} -> invoices
      _ -> []
    end
  end

  @doc """
  Счёт-фактура по идентификатору вместе со сторонами сделки.

  Возвращает `{счёт-фактура, продавец, покупатель}`: продавец — наша
  организация, покупатель — контрагент. Для выданного и полученного
  счёта-фактуры стороны меняются местами.
  """
  @spec load(String.t(), String.t()) ::
          {:ok, {Invoice.t(), struct() | nil, struct() | nil}} | {:error, term()}
  def load(invoice_id, organization_id) do
    with {:ok, invoice} <- fetch(invoice_id, organization_id) do
      organization = fetch_organization(organization_id)
      counterparty = fetch_counterparty(invoice.counterparty_id, organization_id)
      {:ok, {invoice, organization, counterparty}}
    end
  end

  @doc """
  Одна страница журнала: счёт-фактура по идентификатору.
  """
  @spec fetch(String.t(), String.t()) :: {:ok, Invoice.t()} | {:error, term()}
  def fetch(invoice_id, organization_id) do
    Invoice
    |> Ash.Query.filter(id == ^invoice_id)
    |> Ash.Query.load([:counterparty])
    |> Ash.read_one(tenant: organization_id, authorize?: false)
    |> case do
      {:ok, nil} -> {:error, :not_found}
      {:ok, invoice} -> {:ok, invoice}
      {:error, error} -> {:error, error}
    end
  end

  # Стороны сделки для печатной формы и XML: продавец — наша организация.
  # Стороны сделки для печатной формы и XML: продавец — наша организация.
  @spec parties(Invoice.t(), struct() | nil, struct() | nil) :: {struct() | nil, struct() | nil}
  def parties(%{direction: :received} = _invoice, organization, counterparty),
    do: {counterparty, organization}

  def parties(_invoice, organization, counterparty), do: {organization, counterparty}

  defp fetch_organization(nil), do: nil

  defp fetch_organization(organization_id) do
    case Ash.get(Pulse.Core.Organization, organization_id, authorize?: false) do
      {:ok, organization} -> organization
      _ -> nil
    end
  end

  defp fetch_counterparty(nil, _organization_id), do: nil

  defp fetch_counterparty(counterparty_id, organization_id) do
    Pulse.Catalog.Counterparty
    |> Ash.Query.filter(id == ^counterparty_id)
    |> Ash.read_one(tenant: organization_id, authorize?: false)
    |> case do
      {:ok, counterparty} -> counterparty
      _ -> nil
    end
  end

  @doc """
  Итоги по счетам-фактурам: суммы с НДС, без НДС и НДС.

  Основа налоговой отчётности: по выданным считается НДС к уплате,
  по полученным — к зачёту.
  """
  @spec totals([Invoice.t()]) :: map()
  def totals(invoices) do
    gross = sum(invoices, & &1.amount)
    vat = sum(invoices, &(&1.vat_amount || Decimal.new(0)))

    %{
      gross: gross,
      vat: vat,
      net: Decimal.sub(gross, vat)
    }
  end

  # Ставка НДС на дату счёта-фактуры; если параметр не задан, счёт-фактура
  # не формируется — молча ставить неверную ставку нельзя.
  defp vat_rate(date) do
    case Rates.fetch("vat_rate", date) do
      {:ok, rate} -> {:ok, rate.value}
      {:error, reason} -> {:error, reason}
    end
  end

  # Дата документа-основания: у документов учёта это `doc_date`.
  defp document_date(document), do: Map.fetch!(document, :doc_date)

  # Сумма документа: сумма строк. Строка хранит сумму (`amount`), а если
  # она не заполнена — считается по количеству и цене.
  defp document_amount(document) do
    document
    |> lines()
    |> Enum.reduce(Decimal.new(0), fn line, acc ->
      Decimal.add(acc, line_amount(line))
    end)
  end

  defp lines(document) do
    case Map.get(document, :lines) do
      %Ash.NotLoaded{} -> []
      nil -> []
      lines -> lines
    end
  end

  defp line_amount(line), do: line.amount || Decimal.mult(line.quantity, line.price)

  defp number(document, direction) do
    prefix = if direction == :issued, do: "СФ-В", else: "СФ-П"
    "#{prefix}-#{Map.get(document, :number) || document.id}"
  end

  defp sum(invoices, fun) do
    Enum.reduce(invoices, Decimal.new(0), fn invoice, acc -> Decimal.add(acc, fun.(invoice)) end)
  end
end
