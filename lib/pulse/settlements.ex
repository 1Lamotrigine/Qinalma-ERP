defmodule Pulse.Settlements do
  @moduledoc """
  Домен взаиморасчётов: долги по контрагентам и договорам.

  Долги считаются по регистру `Pulse.Ledger.SettlementMovement`:
  движение долга увеличивает задолженность, оплата и зачёт её
  уменьшают. Зачёт аванса выполняется при проведении оплаты
  и реализации (`Pulse.Settlements.Offset`).
  """

  alias Pulse.Ledger.SettlementMovement

  require Ash.Query

  @typedoc """
  Долг по паре «контрагент + договор».

  `:debit` — нам должны, `:credit` — мы должны, `:balance` — разница,
  `:overdue` — просроченная часть, `:advance` — аванс (оплата без
  отгрузки или отгрузка без оплаты).
  """
  @type debt :: %{
          counterparty_id: String.t(),
          contract_id: String.t() | nil,
          debit: Decimal.t(),
          credit: Decimal.t(),
          overdue: Decimal.t(),
          advance: Decimal.t(),
          balance: Decimal.t()
        }

  @doc """
  Долги по контрагентам и договорам на дату.

  `:debit` — нам должны, `:credit` — мы должны, `:balance` — разница,
  `:overdue` — просроченная часть (срок оплаты прошёл).
  """
  @spec debts(String.t(), Date.t(), keyword()) :: [debt()]
  def debts(organization_id, date, opts \\ []) do
    movements = movements_until(organization_id, date, opts)

    movements
    |> Enum.group_by(&{&1.counterparty_id, &1.contract_id})
    |> Enum.map(fn {{counterparty_id, contract_id}, rows} ->
      debit = side_total(rows, :debit)
      credit = side_total(rows, :credit)

      %{
        counterparty_id: counterparty_id,
        contract_id: contract_id,
        debit: debit,
        credit: credit,
        overdue: overdue_total(rows, date),
        advance: advance_total(debit, credit),
        balance: Decimal.sub(debit, credit)
      }
    end)
    |> Enum.reject(&closed?/1)
    |> Enum.sort_by(& &1.counterparty_id)
  end

  @doc """
  Долг одной пары «контрагент + договор» на дату.
  """
  @spec debt(String.t(), String.t(), String.t() | nil, Date.t()) :: debt()
  def debt(organization_id, counterparty_id, contract_id, date) do
    rows =
      organization_id
      |> movements_until(date, [])
      |> Enum.filter(&(&1.counterparty_id == counterparty_id and &1.contract_id == contract_id))

    debit = side_total(rows, :debit)
    credit = side_total(rows, :credit)

    %{
      counterparty_id: counterparty_id,
      contract_id: contract_id,
      debit: debit,
      credit: credit,
      overdue: overdue_total(rows, date),
      advance: advance_total(debit, credit),
      balance: Decimal.sub(debit, credit)
    }
  end

  @doc """
  Движения расчётов по контрагенту за период — для акта сверки.
  """
  @spec reconciliation(String.t(), String.t(), Date.t(), Date.t(), keyword()) ::
          [SettlementMovement.t()]
  def reconciliation(organization_id, counterparty_id, from, to, opts \\ []) do
    contract_id = Keyword.get(opts, :contract_id)

    SettlementMovement
    |> Ash.Query.filter(counterparty_id == ^counterparty_id)
    |> filter_contract(contract_id)
    |> Ash.Query.filter(doc_date >= ^from and doc_date <= ^to)
    |> Ash.Query.sort(doc_date: :asc, inserted_at: :asc)
    |> Ash.read(tenant: organization_id, authorize?: false)
    |> case do
      {:ok, movements} -> movements
      _ -> []
    end
  end

  @doc """
  Итоги акта сверки: сальдо на начало, обороты и сальдо на конец.
  """
  @spec reconciliation_totals(String.t(), String.t(), Date.t(), Date.t(), keyword()) :: map()
  def reconciliation_totals(organization_id, counterparty_id, from, to, opts \\ []) do
    contract_id = Keyword.get(opts, :contract_id)

    before =
      organization_id
      |> movements_until(Date.add(from, -1), opts)
      |> Enum.filter(&(&1.counterparty_id == counterparty_id and &1.contract_id == contract_id))

    within = reconciliation(organization_id, counterparty_id, from, to, opts)

    opening = Decimal.sub(side_total(before, :debit), side_total(before, :credit))
    debit = side_total(within, :debit)
    credit = side_total(within, :credit)

    %{
      opening: opening,
      debit: debit,
      credit: credit,
      closing: Decimal.add(opening, Decimal.sub(debit, credit))
    }
  end

  @doc """
  Остатки денег по кассам и банковским счетам на дату.
  """
  @spec cash_balances(String.t(), Date.t()) :: [map()]
  def cash_balances(organization_id, date) do
    query =
      Pulse.Ledger.CashMovement
      |> Ash.Query.filter(doc_date <= ^date)

    case Ash.read(query, tenant: organization_id, authorize?: false) do
      {:ok, movements} -> group_cash(movements)
      _ -> []
    end
  end

  @doc """
  Остаток по конкретной кассе или счёту.
  """
  @spec cash_balance(String.t(), :cash | :bank, String.t(), Date.t()) :: Decimal.t()
  def cash_balance(organization_id, account_kind, account_id, date) do
    organization_id
    |> cash_balances(date)
    |> Enum.find(&(&1.account_kind == account_kind and &1.account_id == account_id))
    |> case do
      nil -> Decimal.new(0)
      row -> row.amount
    end
  end

  defp group_cash(movements) do
    movements
    |> Enum.group_by(&{&1.account_kind, &1.account_id})
    |> Enum.map(fn {{account_kind, account_id}, rows} ->
      %{
        account_kind: account_kind,
        account_id: account_id,
        amount:
          Enum.reduce(rows, Decimal.new(0), fn row, acc ->
            sign = if row.record_type == :receipt, do: 1, else: -1
            Decimal.add(acc, Decimal.mult(sign, row.amount))
          end)
      }
    end)
    |> Enum.sort_by(& &1.account_id)
  end

  defp movements_until(organization_id, date, opts) do
    contract_id = Keyword.get(opts, :contract_id)

    SettlementMovement
    |> Ash.Query.filter(doc_date <= ^date)
    |> filter_contract(contract_id)
    |> Ash.read(tenant: organization_id, authorize?: false)
    |> case do
      {:ok, movements} -> movements
      _ -> []
    end
  end

  defp filter_contract(query, nil), do: query

  defp filter_contract(query, contract_id),
    do: Ash.Query.filter(query, contract_id == ^contract_id)

  # Задолженность по стороне: долг и зачёт увеличивают её,
  # оплата — уменьшает.
  defp side_total(rows, side) do
    rows
    |> Enum.filter(&(&1.side == side))
    |> Enum.reduce(Decimal.new(0), fn row, acc -> Decimal.add(acc, signed(row)) end)
  end

  # Зачёт и оплата уменьшают задолженность, долг — увеличивает.
  defp signed(%{direction: direction} = row) when direction in [:payment, :offset],
    do: Decimal.negate(row.amount)

  defp signed(row), do: row.amount

  # Просроченная часть: непогашенный долг со сроком оплаты до даты отчёта.
  defp overdue_total(rows, date) do
    rows
    |> Enum.filter(&(&1.due_date && Date.compare(&1.due_date, date) == :lt))
    |> Enum.reduce(Decimal.new(0), fn row, acc -> Decimal.add(acc, signed(row)) end)
    |> then(&max(&1, Decimal.new(0)))
  end

  # Аванс — отрицательное сальдо любой стороны: заплатили, но не получили,
  # или отгрузили, но не оплатили.
  defp advance_total(debit, credit) do
    negative = fn value ->
      if Decimal.compare(value, 0) == :lt, do: Decimal.negate(value), else: Decimal.new(0)
    end

    Decimal.add(negative.(debit), negative.(credit))
  end

  defp closed?(row) do
    Decimal.equal?(row.debit, 0) and Decimal.equal?(row.credit, 0)
  end
end
