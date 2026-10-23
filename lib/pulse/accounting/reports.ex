defmodule Pulse.Accounting.Reports do
  @moduledoc """
  Отчёты бухгалтерского учёта (раздел 5.4 ТЗ).

  Отчёты строятся по журналу проводок: отдельного хранилища итогов
  пока нет, а объём MVP это позволяет. При переходе на помесячные
  `*_totals` меняются только источники данных внутри этого модуля —
  форма ответа остаётся прежней.
  """

  alias Pulse.Accounting.Entries

  @typedoc """
  Строка оборотно-сальдовой ведомости.
  """
  @type turnover_row :: %{
          code: String.t(),
          name: String.t(),
          kind: atom(),
          opening: %{debit: Decimal.t(), credit: Decimal.t()},
          debit: Decimal.t(),
          credit: Decimal.t(),
          closing: %{debit: Decimal.t(), credit: Decimal.t()}
        }

  @doc """
  Оборотно-сальдовая ведомость по всем счетам за период.

  Возвращает строки по счетам, у которых есть остаток или обороты:
  пустые счета в ведомость не попадают, иначе отчёт нечитаем.
  """
  @spec trial_balance(String.t(), Date.t(), Date.t(), keyword()) :: [turnover_row()]
  def trial_balance(organization_id, from, to, opts \\ []) do
    ledger = Keyword.get(opts, :ledger, :accounting)

    Pulse.Accounting.ChartOfAccounts.accounts()
    |> Enum.map(&{&1.code, &1.name, &1.kind})
    |> Enum.map(fn {code, name, kind} ->
      turnover = Entries.turnover(code, organization_id, from, to, ledger: ledger)

      %{
        code: code,
        name: name,
        kind: kind,
        opening: turnover.opening,
        debit: turnover.debit_turnover,
        credit: turnover.credit_turnover,
        closing: turnover.closing
      }
    end)
    |> Enum.reject(&empty_row?/1)
    |> Enum.sort_by(& &1.code)
  end

  @doc """
  Итоги ведомости: суммы по колонкам.

  Проверка сходимости: итог дебета и кредита оборотов совпадают,
  и сальдо начальное сходится с сальдо конечным.
  """
  @spec trial_balance_totals([turnover_row()]) :: map()
  def trial_balance_totals(rows) do
    %{
      opening_debit: sum(rows, & &1.opening.debit),
      opening_credit: sum(rows, & &1.opening.credit),
      debit: sum(rows, & &1.debit),
      credit: sum(rows, & &1.credit),
      closing_debit: sum(rows, & &1.closing.debit),
      closing_credit: sum(rows, & &1.closing.credit)
    }
  end

  @doc """
  Карточка счёта: входящее сальдо, проводки за период, исходящее сальдо.

  Проводки идут в хронологическом порядке; после каждой строки считается
  накопительное сальдо, как в карточке счёта 1С.
  """
  @spec account_card(String.t(), String.t(), Date.t(), Date.t(), keyword()) :: map()
  def account_card(account_code, organization_id, from, to, opts \\ []) do
    ledger = Keyword.get(opts, :ledger, :accounting)

    entries = Entries.entries_for_account(account_code, organization_id, from, to, ledger: ledger)
    opening_entry = Entries.turnover(account_code, organization_id, from, to, ledger: ledger)

    rows =
      entries
      |> Enum.reduce({[], opening_entry.opening}, fn entry, {acc, balance} ->
        {debit, credit} = sides(entry, account_code)

        balance = %{
          debit: Decimal.add(balance.debit, debit),
          credit: Decimal.add(balance.credit, credit)
        }

        {acc ++ [row(entry, debit, credit, balance)], balance}
      end)
      |> elem(0)

    %{
      account_code: account_code,
      opening: opening_entry.opening,
      rows: rows,
      closing: opening_entry.closing,
      debit_turnover: opening_entry.debit_turnover,
      credit_turnover: opening_entry.credit_turnover
    }
  end

  @doc """
  Анализ счёта: обороты в разрезе корреспондирующих счетов.

  Показывает, с какими счетами счёт работает: сколько пришло и ушло
  по каждому корреспондирующему счёту.
  """
  @spec account_analysis(String.t(), String.t(), Date.t(), Date.t(), keyword()) :: [map()]
  def account_analysis(account_code, organization_id, from, to, opts \\ []) do
    ledger = Keyword.get(opts, :ledger, :accounting)

    by_correspondent =
      account_code
      |> Entries.entries_for_account(organization_id, from, to, ledger: ledger)
      |> Enum.group_by(&correspondent(&1, account_code))

    by_correspondent
    |> Enum.map(fn {code, entries} ->
      {debit, credit} =
        Enum.reduce(entries, {Decimal.new(0), Decimal.new(0)}, fn entry, {d, c} ->
          {entry_debit, entry_credit} = sides(entry, account_code)
          {Decimal.add(d, entry_debit), Decimal.add(c, entry_credit)}
        end)

      %{code: code, name: account_name(code), debit: debit, credit: credit}
    end)
    |> Enum.sort_by(& &1.code)
  end

  @doc """
  Главная книга: обороты по счетам с раскрытием корреспонденции.

  Для каждого счёта, у которого есть движения, — строки анализа
  и итоги; структура повторяет главную книгу 1С.
  """
  @spec general_ledger(String.t(), Date.t(), Date.t(), keyword()) :: [map()]
  def general_ledger(organization_id, from, to, opts \\ []) do
    organization_id
    |> trial_balance(from, to, opts)
    |> Enum.map(fn row ->
      %{
        code: row.code,
        name: row.name,
        opening: row.opening,
        closing: row.closing,
        debit_turnover: row.debit,
        credit_turnover: row.credit,
        analysis: account_analysis(row.code, organization_id, from, to, opts)
      }
    end)
  end

  defp row(entry, debit, credit, balance) do
    %{
      entry: entry,
      doc_date: entry.doc_date,
      content: entry.content,
      debit: debit,
      credit: credit,
      balance: balance
    }
  end

  defp sides(entry, account_code) do
    debit = if entry.debit_account_code == account_code, do: entry.amount, else: Decimal.new(0)
    credit = if entry.credit_account_code == account_code, do: entry.amount, else: Decimal.new(0)
    {debit, credit}
  end

  defp correspondent(entry, account_code) do
    if entry.debit_account_code == account_code do
      entry.credit_account_code
    else
      entry.debit_account_code
    end
  end

  defp account_name(code) do
    case Enum.find(Pulse.Accounting.ChartOfAccounts.accounts(), &(&1.code == code)) do
      nil -> code
      account -> account.name
    end
  end

  defp empty_row?(row) do
    zero?(row.opening.debit) and zero?(row.opening.credit) and zero?(row.debit) and
      zero?(row.credit) and zero?(row.closing.debit) and zero?(row.closing.credit)
  end

  defp zero?(value), do: Decimal.equal?(value, 0)

  defp sum(rows, fun) do
    Enum.reduce(rows, Decimal.new(0), fn row, acc -> Decimal.add(acc, fun.(row)) end)
  end
end
