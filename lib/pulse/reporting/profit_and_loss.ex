defmodule Pulse.Reporting.ProfitAndLoss do
  @moduledoc """
  Отчёт о прибылях и убытках для руководителя (раздел 5.4 ТЗ).

  Строится по оборотам счетов доходов и расходов:

    * доходы — счета 6XXX (кредитовый оборот);
    * расходы — счета 7XXX (дебетовый оборот);
    * прибыль — разница.

  Отчёт не заменяет бухгалтерские формы: он показывает динамику
  крупными мазками, чтобы руководитель видел картину месяца.
  """

  alias Pulse.Accounting.Entries

  @doc """
  Отчёт за период: доходы, расходы и прибыль с разбивкой по счетам.
  """
  @spec report(String.t(), Date.t(), Date.t()) :: map()
  def report(organization_id, from, to) do
    accounts = Pulse.Accounting.ChartOfAccounts.accounts()

    income = section(accounts, organization_id, from, to, "6")
    expenses = section(accounts, organization_id, from, to, "7")

    income_total = sum(income)
    expense_total = sum(expenses)

    %{
      from: from,
      to: to,
      income: income,
      expenses: expenses,
      income_total: income_total,
      expense_total: expense_total,
      profit: Decimal.sub(income_total, expense_total)
    }
  end

  @doc """
  Динамика прибыли по месяцам за год.

  Возвращает список месяцев с доходами, расходами и прибылью —
  основа графика «динамика» в отчётах руководителя.
  """
  @spec dynamics(String.t(), Date.t(), non_neg_integer()) :: [map()]
  def dynamics(organization_id, date, months \\ 6) do
    date
    |> previous_months(months)
    |> Enum.map(fn period ->
      {from, to} = Pulse.Accounting.Totals.period_bounds(period)
      report = report(organization_id, from, to)

      %{
        period: period,
        income: report.income_total,
        expenses: report.expense_total,
        profit: report.profit
      }
    end)
  end

  @doc """
  Оборачиваемость запасов за период.

  Средний остаток за период и себестоимость проданного: частное
  показывает, сколько раз запас обернулся.
  """
  @spec inventory_turnover(String.t(), Date.t(), Date.t()) :: map()
  def inventory_turnover(organization_id, from, to) do
    totals = Pulse.Accounting.Totals.for_period(organization_id, period_of(from))

    average_cost =
      totals.stock
      |> Enum.reduce(Decimal.new(0), fn row, acc -> Decimal.add(acc, row.closing_cost) end)

    sold =
      totals.stock
      |> Enum.reduce(Decimal.new(0), fn row, acc -> Decimal.add(acc, row.expense_cost) end)

    %{
      from: from,
      to: to,
      average_cost: average_cost,
      sold_cost: sold,
      turnover: ratio(sold, average_cost)
    }
  end

  defp section(accounts, organization_id, from, to, prefix) do
    accounts
    |> Enum.filter(&String.starts_with?(&1.code, prefix))
    |> Enum.map(fn account ->
      turnover = Entries.turnover(account.code, organization_id, from, to)

      amount =
        if prefix == "6", do: turnover.credit_turnover, else: turnover.debit_turnover

      %{code: account.code, name: account.name, amount: amount}
    end)
    |> Enum.reject(&Decimal.equal?(&1.amount, 0))
    |> Enum.sort_by(& &1.code)
  end

  defp sum(rows) do
    Enum.reduce(rows, Decimal.new(0), &Decimal.add(&2, &1.amount))
  end

  defp previous_months(date, count) do
    date
    |> List.duplicate(count)
    |> Enum.with_index()
    |> Enum.map(fn {_date, index} -> shift_months(date, -index) end)
    |> Enum.reverse()
  end

  defp shift_months(date, offset) do
    month = date.month + offset
    year = date.year + div(month - 1, 12)
    normalized = rem(month - 1 + 12, 12) + 1
    %Date{year: year, month: normalized, day: 1}
  end

  # Оборачиваемость при нулевом остатке не определена — возвращаем ноль,
  # а не деление на ноль.
  defp ratio(numerator, denominator) do
    if Decimal.equal?(denominator, 0) do
      Decimal.new(0)
    else
      Decimal.div(numerator, denominator)
    end
  end

  defp period_of(%Date{year: year, month: month}), do: %Date{year: year, month: month, day: 1}
end
