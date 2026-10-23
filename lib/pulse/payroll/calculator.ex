defmodule Pulse.Payroll.Calculator do
  @moduledoc """
  Расчёт заработной платы по законодательным параметрам (раздел 5.5 ТЗ).

  Чистые функции: на вход начисленная сумма и набор параметров закона,
  на выход — удержания, взносы и налог. Параметры берутся из
  `statutory_rates` на дату (`Pulse.Tax.Rates`), а не из констант: смена
  ставки не требует релиза.

  Порядок расчёта для работника (по действующей редакции НК РК):

    1. ОПВ — 10 % от начисленного, в пределах `opv_cap_mzp` МЗП;
    2. ВОСМС — 2 % от начисленного, удерживается с работника;
    3. ИПН — 10 % от (начислено − ОПВ − ВОСМС − вычет), вычет —
       `deduction_monthly` МРП в месяц;
    4. СО — 3.5 % от (начислено − ОПВ), в пределах `so_cap_mzp` МЗП
       (платит работодатель);
    5. ОПВР — 1.5 % от начисленного (платит работодатель);
    6. ООСМС — 3 % от начисленного, в пределах `oosms_cap_mzp` МЗП
       (платит работодатель).

  **Внимание.** Значения — ориентир, а не проверенная истина: их нужно
  сверить с бухгалтером (открытые вопросы этапа 8).
  """

  alias Pulse.Tax.Rates

  @typedoc """
  Результат расчёта по одному работнику.
  """
  @type result :: %{
          gross: Decimal.t(),
          opv: Decimal.t(),
          vosms: Decimal.t(),
          ipn: Decimal.t(),
          so: Decimal.t(),
          opvr: Decimal.t(),
          oosms: Decimal.t(),
          deductions: Decimal.t(),
          employer: Decimal.t(),
          net: Decimal.t(),
          total: Decimal.t()
        }

  @doc """
  Считает зарплату по начисленной сумме и параметрам на дату.

  `rates` — карта «код → значение» из `Pulse.Tax.Rates.current/1`.
  """
  @spec calculate(Decimal.t(), map(), Date.t()) :: {:ok, result()} | {:error, String.t()}
  def calculate(gross, rates, date) do
    with {:ok, values} <- fetch_rates(rates, date) do
      {:ok, compute(gross, values)}
    end
  end

  @doc """
  Считает по карте значений; отсутствующие коды считаются нулевыми.

  Удобно для тестов: значения задаются прямо в тесте.
  """
  @spec calculate_with_values(Decimal.t(), map()) :: result()
  def calculate_with_values(gross, values) do
    compute(gross, values)
  end

  @doc """
  Параметры расчёта на дату как карта «код → значение».

  Отсутствие параметра — ошибка: молча подставить неверную ставку хуже,
  чем явно отказать (как в `Pulse.Tax.Rates`).
  """
  @spec rates_on(Date.t()) :: {:ok, map()} | {:error, String.t()}
  def rates_on(date) do
    rates = Map.new(Rates.current(date), &{&1.code, &1.value})

    case fetch_rates(rates, date) do
      {:ok, _values} -> {:ok, rates}
      {:error, error} -> {:error, error}
    end
  end

  # Обязательные для расчёта параметры: без них зарплату не посчитать.
  @required ~w(opv vosms ipn so opvr oosms mrp mzp deduction_monthly)

  defp fetch_rates(rates, date) do
    case Enum.find(@required, &(not Map.has_key?(rates, &1))) do
      nil ->
        {:ok, rates}

      code ->
        {:error, "не задан параметр «#{code}» на #{Date.to_string(date)}"}
    end
  end

  defp compute(gross, values) do
    mzp = value(values, "mzp")
    opv_cap = Decimal.mult(value(values, "opv_cap_mzp"), mzp)
    so_cap = Decimal.mult(value(values, "so_cap_mzp"), mzp)
    oosms_cap = Decimal.mult(value(values, "oosms_cap_mzp"), mzp)
    opvr_cap = Decimal.mult(value(values, "opvr_cap_mzp"), mzp)

    opv = percent(gross, values, "opv", cap: opv_cap)
    vosms = percent(gross, values, "vosms")
    deduction = Decimal.mult(value(values, "deduction_monthly"), value(values, "mrp"))

    ipn_base = clamp_minus(gross, [opv, vosms, deduction])
    ipn = percent(ipn_base, values, "ipn")

    opvr_base = cap_base(gross, opvr_cap)
    opvr = percent(opvr_base, values, "opvr")

    so_base = cap_base(Decimal.sub(gross, opv), so_cap)
    so = percent(so_base, values, "so")

    oosms_base = cap_base(gross, oosms_cap)
    oosms = percent(oosms_base, values, "oosms")

    deductions = Decimal.add(Decimal.add(opv, vosms), ipn)
    employer = Decimal.add(Decimal.add(so, opvr), oosms)

    %{
      gross: round2(gross),
      opv: round2(opv),
      vosms: round2(vosms),
      ipn: round2(ipn),
      so: round2(so),
      opvr: round2(opvr),
      oosms: round2(oosms),
      deductions: round2(deductions),
      employer: round2(employer),
      net: round2(Decimal.sub(gross, deductions)),
      total: round2(Decimal.add(gross, employer))
    }
  end

  # Начисление минус удержания, но не ниже нуля.
  defp clamp_minus(gross, deductions) do
    result = Enum.reduce(deductions, gross, &Decimal.sub(&2, &1))
    if Decimal.compare(result, 0) == :lt, do: Decimal.new(0), else: result
  end

  # База взноса, ограниченная пределом сверху.
  defp cap_base(amount, cap) do
    if Decimal.compare(cap, 0) == :gt and Decimal.compare(amount, cap) == :gt do
      cap
    else
      amount
    end
  end

  defp percent(amount, values, code, opts \\ []) do
    base =
      case Keyword.get(opts, :cap) do
        nil -> amount
        cap -> cap_base(amount, cap)
      end

    base
    |> Decimal.mult(value(values, code))
    |> Decimal.div(100)
  end

  defp value(values, code), do: Map.get(values, code, Decimal.new(0))

  defp round2(value), do: Decimal.round(value, 2, :half_up)
end
