defmodule Pulse.Posting.SalesShipment do
  @moduledoc """
  Правило проведения реализации ТМЗ.

  Расходует товары со склада: себестоимость берётся по средней
  взвешенной на дату документа. Перед формированием движений правило
  проверяет остатки — расход «в минус» запрещён учётной политикой MVP.
  """
  @behaviour Pulse.Posting.Rule

  alias Pulse.Accounting.Templates
  alias Pulse.Ledger.SettlementMovement
  alias Pulse.Posting.Context
  alias Pulse.Posting.Stock

  @impl true
  def movements(document, context) do
    build(document, context, lines(document))
  end

  @impl true
  def lock_keys(document, _mode) do
    [{:warehouse, document.warehouse_id} | nomenclature_keys(document)]
  end

  @impl true
  def check_balances(document) do
    context = Context.build(document, nil)

    Enum.reduce_while(lines(document), :ok, fn line, :ok ->
      balance =
        Context.balance(context, document.warehouse_id, line.nomenclature_id, document.doc_date)

      if Decimal.compare(balance.quantity, line.quantity) == :lt do
        message =
          "недостаточно ТМЗ: требуется #{line.quantity}, доступно #{balance.quantity}"

        {:halt, {:error, message}}
      else
        {:cont, :ok}
      end
    end)
  end

  @impl true
  def ledger_movements(document, context) do
    with {:ok, movements} <- movements(document, context),
         {:ok, settlements} <- settlement_movements(document) do
      {:ok,
       [
         {Pulse.Ledger.StockMovement, movements},
         {SettlementMovement, settlements}
       ]}
    end
  end

  @impl true
  def entries(document, _context) do
    attrs = %{
      amount: revenue(document),
      content: "Реализация ТМЗ и услуг",
      debit_subaccounts: [subaccount("counterparty", document)],
      credit_subaccounts: [subaccount("nomenclature", document)]
    }

    Templates.build(:shipment_tmz, document, attrs)
  end

  defp build(document, context, lines) do
    Enum.reduce_while(lines, {:ok, []}, fn line, {:ok, acc} ->
      balance =
        Context.balance(context, document.warehouse_id, line.nomenclature_id, document.doc_date)

      unit_cost = Stock.unit_cost(balance.quantity, balance.cost)
      cost = Decimal.mult(unit_cost, line.quantity)

      movement = %{
        document_type: document_type(),
        document_id: document.id,
        document_line_id: line.id,
        record_type: :expense,
        period: period(document.doc_date),
        doc_date: document.doc_date,
        quantity: line.quantity,
        cost: cost,
        warehouse_id: document.warehouse_id,
        nomenclature_id: line.nomenclature_id
      }

      {:cont, {:ok, acc ++ [movement]}}
    end)
  end

  @doc false
  def document_type, do: Pulse.Accounting.Posting.document_type(%Pulse.Sales.Shipment{})

  @doc false
  def period(date), do: %Date{year: date.year, month: date.month, day: 1}

  @doc """
  Выручка документа: сумма строк по ценам продажи.
  """
  @spec revenue(struct()) :: Decimal.t()
  def revenue(document) do
    document
    |> lines()
    |> Enum.reduce(Decimal.new(0), fn line, acc -> Decimal.add(acc, line_amount(line)) end)
  end

  defp line_amount(line), do: line.amount || Decimal.mult(line.quantity, line.price)

  defp subaccount("nomenclature", document) do
    case lines(document) do
      [line | _] -> %{"type" => "nomenclature", "id" => line.nomenclature_id}
      [] -> %{}
    end
  end

  defp subaccount("counterparty", document) do
    %{"type" => "counterparty", "id" => document.counterparty_id}
  end

  # Реализация создаёт долг покупателя: дебетовая сторона растёт
  # на выручку. Аванс покупателя зачитывается сам: сальдо по стороне
  # считается как сумма движений, поэтому долг и оплата гасят друг друга.
  defp settlement_movements(document) do
    amount = revenue(document)

    {:ok,
     [
       %{
         document_type: document_type(),
         document_id: document.id,
         counterparty_id: document.counterparty_id,
         contract_id: document.contract_id,
         direction: :debt,
         side: :debit,
         period: period(document.doc_date),
         doc_date: document.doc_date,
         amount: amount,
         currency_id: document.currency_id,
         amount_currency: amount,
         due_date: nil
       }
     ]}
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
end
