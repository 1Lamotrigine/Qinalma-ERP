defmodule Pulse.Reporting do
  @moduledoc """
  Домен сводных показателей: виджеты начальной страницы и монитор
  руководителя.

  Все цифры считаются по регистрам и журналу проводок
  (`Pulse.Settlements`, `Pulse.Ledger`), а не хранятся отдельно.
  Это осознанный компромисс MVP: объём данных позволяет считать
  «на лету», а при росте появится слой помесячных итогов.
  """

  alias Pulse.Settlements

  @doc """
  Показатели дня для начальной страницы и монитора руководителя.

  Возвращает деньги по кассам и счетам, долги покупателей и поставщиков
  и продажи за период.
  """
  @spec dashboard(String.t(), Date.t()) :: map()
  def dashboard(organization_id, date) do
    %{
      date: date,
      cash: cash_widget(organization_id, date),
      customers: customers_widget(organization_id, date),
      suppliers: suppliers_widget(organization_id, date),
      sales: sales_widget(organization_id, date)
    }
  end

  @doc """
  Остатки денег: касса, банк и итог.
  """
  @spec cash_widget(String.t(), Date.t()) :: map()
  def cash_widget(organization_id, date) do
    balances = Settlements.cash_balances(organization_id, date)

    cash = total_of(balances, :cash)
    bank = total_of(balances, :bank)

    %{
      cash: cash,
      bank: bank,
      total: Decimal.add(cash, bank)
    }
  end

  @doc """
  Долги покупателей: задолженность, просроченная часть и авансы.
  """
  @spec customers_widget(String.t(), Date.t()) :: map()
  def customers_widget(organization_id, date) do
    rows = Settlements.debts(organization_id, date)

    %{
      total: sum(rows, fn row -> positive(row.debit) end),
      overdue: sum(rows, & &1.overdue),
      advance: sum(rows, & &1.advance)
    }
  end

  @doc """
  Долги поставщикам: задолженность, просроченная часть и авансы.
  """
  @spec suppliers_widget(String.t(), Date.t()) :: map()
  def suppliers_widget(organization_id, date) do
    rows = Settlements.debts(organization_id, date)

    %{
      total: sum(rows, fn row -> positive(row.credit) end),
      overdue: sum(rows, & &1.overdue),
      advance: sum(rows, & &1.advance)
    }
  end

  @doc """
  Продажи: за текущий месяц, с начала года и за прошлый месяц.

  Продажи считаются по проводкам счёта 6010 (доход от реализации),
  поэтому цифры совпадают с бухгалтерскими отчётами.
  """
  @spec sales_widget(String.t(), Date.t()) :: map()
  def sales_widget(organization_id, date) do
    month_start = %Date{year: date.year, month: date.month, day: 1}
    year_start = %Date{year: date.year, month: 1, day: 1}
    previous_month_end = Date.add(month_start, -1)

    previous_month_start = %Date{
      year: previous_month_end.year,
      month: previous_month_end.month,
      day: 1
    }

    %{
      month: revenue(organization_id, month_start, date),
      year: revenue(organization_id, year_start, date),
      previous_month: revenue(organization_id, previous_month_start, previous_month_end)
    }
  end

  @doc """
  Выручка за период по счёту 6010.
  """
  @spec revenue(String.t(), Date.t(), Date.t()) :: Decimal.t()
  def revenue(organization_id, from, to) do
    turnover = Pulse.Accounting.Entries.turnover("6010", organization_id, from, to)
    turnover.credit_turnover
  end

  defp total_of(balances, kind) do
    balances
    |> Enum.filter(&(&1.account_kind == kind))
    |> sum(& &1.amount)
  end

  defp positive(value) do
    if Decimal.compare(value, 0) == :gt, do: value, else: Decimal.new(0)
  end

  defp sum(rows, fun) do
    Enum.reduce(rows, Decimal.new(0), fn row, acc -> Decimal.add(acc, fun.(row)) end)
  end
end
