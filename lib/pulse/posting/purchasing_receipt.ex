defmodule Pulse.Posting.PurchasingReceipt do
  @moduledoc """
  Правило проведения поступления ТМЗ и услуг.

  Каждая строка даёт приход на склад: количество и сумма строки
  (количество × цена). Расчёт чистой функции: строки документа —
  это данные, а не запрос к БД, поэтому правило тестируется без неё.
  """
  @behaviour Pulse.Posting.Rule

  alias Pulse.Accounting.Templates
  alias Pulse.Ledger.SettlementMovement
  alias Pulse.Posting.Context

  @impl true
  def movements(document, _context) do
    movements =
      for line <- lines(document) do
        %{
          document_type: document_type(),
          document_id: document.id,
          document_line_id: line.id,
          record_type: :receipt,
          period: period(document.doc_date),
          doc_date: document.doc_date,
          quantity: line.quantity,
          cost: line_amount(line),
          warehouse_id: document.warehouse_id,
          nomenclature_id: line.nomenclature_id
        }
      end

    {:ok, movements}
  rescue
    _error -> {:error, "не удалось сформировать движения поступления"}
  end

  @impl true
  def lock_keys(document, _mode) do
    [{:warehouse, document.warehouse_id} | nomenclature_keys(document)]
  end

  @impl true
  def check_balances(_document), do: :ok

  @impl true
  def ledger_movements(document, context) do
    with {:ok, movements} <- movements(document, context) do
      {:ok,
       [
         {Pulse.Ledger.StockMovement, movements},
         {SettlementMovement, settlement_movements(document)}
       ]}
    end
  end

  @impl true
  def entries(document, _context) do
    attrs = %{
      amount: total_amount(document),
      content: "Поступление ТМЗ и услуг",
      debit_subaccounts: [subaccount("nomenclature", document)],
      credit_subaccounts: [subaccount("counterparty", document)]
    }

    Templates.build(:receipt_tmz, document, attrs)
  end

  @doc """
  Сумма строки: количество × цена.
  """
  @spec line_amount(struct()) :: Decimal.t()
  def line_amount(line) do
    line.amount || Decimal.mult(line.quantity, line.price)
  end

  # Поступление создаёт кредиторскую задолженность: мы должны
  # поставщику. Аванс выданный зачитывается сам — сальдо по стороне
  # считается как сумма движений.
  defp settlement_movements(document) do
    amount = total_amount(document)

    [
      %{
        document_type: document_type(),
        document_id: document.id,
        counterparty_id: document.counterparty_id,
        contract_id: document.contract_id,
        direction: :credit,
        side: :credit,
        period: period(document.doc_date),
        doc_date: document.doc_date,
        amount: amount,
        currency_id: document.currency_id,
        amount_currency: amount,
        due_date: nil
      }
    ]
  end

  @doc """
  Итог документа по строкам.
  """
  @spec total_amount(struct()) :: Decimal.t()
  def total_amount(document) do
    document
    |> lines()
    |> Enum.reduce(Decimal.new(0), fn line, acc -> Decimal.add(acc, line_amount(line)) end)
  end

  @doc false
  def document_type, do: Pulse.Accounting.Posting.document_type(%Pulse.Purchasing.Receipt{})

  @doc false
  def period(date), do: %Date{year: date.year, month: date.month, day: 1}

  # Субконто проводки: вид аналитики и значение. Для поступления
  # номенклатура берётся из первой строки, контрагент — из документа.
  defp subaccount("nomenclature", document) do
    case lines(document) do
      [line | _] -> %{"type" => "nomenclature", "id" => line.nomenclature_id}
      [] -> %{}
    end
  end

  defp subaccount("counterparty", document) do
    %{"type" => "counterparty", "id" => document.counterparty_id}
  end

  defp lines(document) do
    case document.lines do
      %Ash.NotLoaded{} -> []
      lines -> lines
    end
  end

  defp nomenclature_keys(document) do
    document
    |> lines()
    |> Enum.map(&{:nomenclature, &1.nomenclature_id})
  end

  @doc false
  def context(document, actor, opts \\ []), do: Context.build(document, actor, opts)
end
