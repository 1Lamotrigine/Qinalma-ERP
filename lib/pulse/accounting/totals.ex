defmodule Pulse.Accounting.Totals do
  @moduledoc """
  Помесячные итоги учёта (раздел 5.2 ТЗ).

  Итоги считаются по регистрам и журналу проводок и фиксируются
  при закрытии месяца. Остаток на дату = итог на начало месяца плюс
  движения месяца.

  Отдельной таблицы `*_totals` пока нет: при объёмах MVP пересчёт
  «на лету» быстрее и не расходится с движениями. Когда появится
  потребность в скорости, поменяется только внутренность этого модуля —
  форма ответа останется прежней.
  """

  alias Pulse.Accounting.Entries
  alias Pulse.Ledger.CashMovement
  alias Pulse.Ledger.SettlementMovement
  alias Pulse.Ledger.StockMovement

  require Ash.Query

  @doc """
  Итоги месяца: склад, деньги, расчёты и обороты по счетам.

  Это то, что фиксируется при закрытии периода.
  """
  @spec for_period(String.t(), Date.t()) :: map()
  def for_period(organization_id, period) do
    {from, to} = period_bounds(period)

    %{
      period: period,
      from: from,
      to: to,
      stock: stock_totals(organization_id, from, to),
      cash: cash_totals(organization_id, from, to),
      settlements: settlement_totals(organization_id, from, to),
      accounts: account_totals(organization_id, from, to)
    }
  end

  @doc """
  Итоги склада: приход, расход и остаток по номенклатуре и складу.
  """
  @spec stock_totals(String.t(), Date.t(), Date.t()) :: [map()]
  def stock_totals(organization_id, from, to) do
    organization_id
    |> read_movements(StockMovement, from, to)
    |> Enum.group_by(&{&1.warehouse_id, &1.nomenclature_id})
    |> Enum.map(fn {{warehouse_id, nomenclature_id}, rows} ->
      receipt = sum(rows, &only(&1, :receipt))
      expense = sum(rows, &only(&1, :expense))

      %{
        warehouse_id: warehouse_id,
        nomenclature_id: nomenclature_id,
        receipt_quantity: receipt.quantity,
        receipt_cost: receipt.cost,
        expense_quantity: expense.quantity,
        expense_cost: expense.cost,
        closing_quantity: Decimal.sub(receipt.quantity, expense.quantity),
        closing_cost: Decimal.sub(receipt.cost, expense.cost)
      }
    end)
    |> Enum.sort_by(&{&1.warehouse_id, &1.nomenclature_id})
  end

  @doc """
  Итоги денег: приход, расход и остаток по кассе или счёту.
  """
  @spec cash_totals(String.t(), Date.t(), Date.t()) :: [map()]
  def cash_totals(organization_id, from, to) do
    organization_id
    |> read_movements(CashMovement, from, to)
    |> Enum.group_by(&{&1.account_kind, &1.account_id})
    |> Enum.map(fn {{account_kind, account_id}, rows} ->
      receipt = sum(rows, &only(&1, :receipt))
      expense = sum(rows, &only(&1, :expense))

      %{
        account_kind: account_kind,
        account_id: account_id,
        receipt_amount: receipt.amount,
        expense_amount: expense.amount,
        closing_amount: Decimal.sub(receipt.amount, expense.amount)
      }
    end)
    |> Enum.sort_by(& &1.account_id)
  end

  @doc """
  Итоги расчётов: долг и оплата по паре «контрагент + договор».
  """
  @spec settlement_totals(String.t(), Date.t(), Date.t()) :: [map()]
  def settlement_totals(organization_id, from, to) do
    organization_id
    |> read_movements(SettlementMovement, from, to)
    |> Enum.group_by(&{&1.counterparty_id, &1.contract_id})
    |> Enum.map(fn {{counterparty_id, contract_id}, rows} ->
      %{
        counterparty_id: counterparty_id,
        contract_id: contract_id,
        debit: settlement_side(rows, :debit),
        credit: settlement_side(rows, :credit)
      }
    end)
    |> Enum.sort_by(&{&1.counterparty_id, &1.contract_id})
  end

  @doc """
  Обороты по счетам за месяц.
  """
  @spec account_totals(String.t(), Date.t(), Date.t()) :: [map()]
  def account_totals(organization_id, from, to) do
    Pulse.Accounting.ChartOfAccounts.accounts()
    |> Enum.map(fn account ->
      turnover = Entries.turnover(account.code, organization_id, from, to)

      %{
        code: account.code,
        name: account.name,
        debit: turnover.debit_turnover,
        credit: turnover.credit_turnover
      }
    end)
    |> Enum.reject(&(zero?(&1.debit) and zero?(&1.credit)))
  end

  @doc """
  Границы месяца: первое и последнее число.
  """
  @spec period_bounds(Date.t()) :: {Date.t(), Date.t()}
  def period_bounds(period) do
    from = %Date{year: period.year, month: period.month, day: 1}
    {from, Date.end_of_month(from)}
  end

  defp read_movements(organization_id, resource, from, to) do
    resource
    |> Ash.Query.filter(doc_date >= ^from and doc_date <= ^to)
    |> Ash.read(tenant: organization_id, authorize?: false)
    |> case do
      {:ok, movements} -> movements
      _ -> []
    end
  end

  # Сумма по движениям одного вида: приход или расход.
  defp sum(rows, pick) do
    rows
    |> Enum.filter(&(&1.record_type in [:receipt, :expense]))
    |> Enum.reduce(%{quantity: zero(), cost: zero(), amount: zero()}, fn row, acc ->
      values = pick.(row)
      Map.merge(acc, values, fn _key, left, right -> Decimal.add(left, right) end)
    end)
  end

  defp only(row, type) do
    if row.record_type == type do
      %{
        quantity: Map.get(row, :quantity, zero()),
        cost: Map.get(row, :cost, zero()),
        amount: Map.get(row, :amount, zero())
      }
    else
      %{quantity: zero(), cost: zero(), amount: zero()}
    end
  end

  defp settlement_side(rows, side) do
    rows
    |> Enum.filter(&(&1.side == side))
    |> Enum.reduce(zero(), fn row, acc ->
      sign = if row.direction in [:payment, :offset], do: -1, else: 1
      Decimal.add(acc, Decimal.mult(sign, row.amount))
    end)
  end

  defp zero, do: Decimal.new(0)
  defp zero?(value), do: Decimal.equal?(value, 0)
end
