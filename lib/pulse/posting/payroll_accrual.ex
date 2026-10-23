defmodule Pulse.Posting.PayrollAccrual do
  @moduledoc """
  Правило проведения начисления заработной платы.

  Проведение ведомости пишет:

    * движения регистра зарплаты по каждому сотруднику — начислено,
      ОПВ, ВОСМС, ИПН (удержания) и СО, ОПВР, ООСМС (взносы и
      отчисления работодателя);
    * проводки: начисление (Дт расходы Кт 3350), удержания
      (Дт 3350 Кт 3430/3120) и взносы работодателя (Дт расходы
      Кт 3130/3140).

  Суммы берутся из строк ведомости: расчёт уже сделан при заполнении
  (`Pulse.Payroll.Calculator`), проведение их не пересчитывает.
  """
  @behaviour Pulse.Posting.Rule

  alias Pulse.Accounting.Templates
  alias Pulse.Ledger.PayrollMovement

  @impl true
  def movements(_document, _context), do: {:ok, []}

  @impl true
  def ledger_movements(document, _context) do
    {:ok, [{PayrollMovement, register_movements(document)}]}
  end

  @impl true
  def entries(document, _context) do
    entries =
      accrual_entries(document) ++ deduction_entries(document) ++ employer_entries(document)

    validate(entries)
  end

  @impl true
  def lock_keys(_document, _mode), do: []

  @impl true
  def check_balances(_document), do: :ok

  @doc """
  Тип документа в регистрах.
  """
  @spec document_type(struct()) :: String.t()
  def document_type(document), do: Pulse.Accounting.Posting.document_type(document)

  @doc """
  Итоги ведомости по колонкам.
  """
  @spec totals(struct()) :: map()
  def totals(document) do
    document
    |> lines()
    |> Enum.reduce(zero_totals(), fn line, acc ->
      %{
        gross: Decimal.add(acc.gross, line.gross),
        opv: Decimal.add(acc.opv, line.opv || zero()),
        vosms: Decimal.add(acc.vosms, line.vosms || zero()),
        ipn: Decimal.add(acc.ipn, line.ipn || zero()),
        so: Decimal.add(acc.so, line.so || zero()),
        opvr: Decimal.add(acc.opvr, line.opvr || zero()),
        oosms: Decimal.add(acc.oosms, line.oosms || zero()),
        net: Decimal.add(acc.net, line.net || zero())
      }
    end)
  end

  defp zero_totals do
    %{
      gross: zero(),
      opv: zero(),
      vosms: zero(),
      ipn: zero(),
      so: zero(),
      opvr: zero(),
      oosms: zero(),
      net: zero()
    }
  end

  # --- регистр ---------------------------------------------------------------

  defp register_movements(document) do
    document
    |> lines()
    |> Enum.flat_map(&line_movements(document, &1))
  end

  defp line_movements(document, line) do
    [
      {"gross", line.gross},
      {"opv", line.opv},
      {"vosms", line.vosms},
      {"ipn", line.ipn},
      {"so", line.so},
      {"opvr", line.opvr},
      {"oosms", line.oosms}
    ]
    |> Enum.reject(fn {_kind, amount} -> is_nil(amount) or Decimal.equal?(amount, 0) end)
    |> Enum.map(fn {kind, amount} ->
      %{
        document_type: document_type(document),
        document_id: document.id,
        document_line_id: line.id,
        employee_id: line.employee_id,
        kind: String.to_existing_atom(kind),
        period: period(document.doc_date),
        doc_date: document.doc_date,
        amount: amount,
        currency_id: document.currency_id,
        amount_currency: amount
      }
    end)
  end

  # --- проводки --------------------------------------------------------------

  defp accrual_entries(document) do
    totals = totals(document)

    if positive?(totals.gross) do
      [entry(:payroll_accrual, document, totals.gross, "Начислена заработная плата")]
    else
      []
    end
  end

  defp deduction_entries(document) do
    totals = totals(document)

    ipn =
      if positive?(totals.ipn),
        do: [entry(:payroll_ipn, document, totals.ipn, "Удержан ИПН")],
        else: []

    opv_vosms = Decimal.add(totals.opv, totals.vosms)

    opv =
      if positive?(opv_vosms),
        do: [entry(:payroll_opv, document, opv_vosms, "Удержаны ОПВ и ВОСМС")],
        else: []

    ipn ++ opv
  end

  defp employer_entries(document) do
    totals = totals(document)
    employer = Decimal.add(totals.so, Decimal.add(totals.opvr, totals.oosms))

    if positive?(employer) do
      [entry(:payroll_employer, document, employer, "Взносы и отчисления работодателя")]
    else
      []
    end
  end

  defp entry(kind, document, amount, content) do
    attrs = %{amount: amount, content: content, ledger: :accounting}

    {:ok, [entry]} = Templates.build(kind, document, attrs)
    entry
  end

  # Проводки должны сходиться: дебет равен кредиту по каждому элементу
  # (каждая проводка даёт одинаковую сумму в дебет и в кредит), поэтому
  # проверяем, что суммы положительны.
  defp validate(entries) do
    if Enum.all?(entries, &(Decimal.compare(&1.amount, 0) == :gt)) do
      {:ok, entries}
    else
      {:error, "некорректная сумма проводки в ведомости"}
    end
  end

  defp lines(document) do
    case document.lines do
      %Ash.NotLoaded{} -> []
      lines -> lines
    end
  end

  defp period(%Date{year: year, month: month}), do: %Date{year: year, month: month, day: 1}

  defp positive?(nil), do: false
  defp positive?(value), do: Decimal.compare(value, 0) == :gt

  defp zero, do: Decimal.new(0)
end
