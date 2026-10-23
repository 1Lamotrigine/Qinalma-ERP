defmodule Pulse.Payroll.CalculatorTest do
  @moduledoc """
  Расчёт заработной платы (этап 8).

  Критерий этапа: расчёт использует параметры закона из `statutory_rates`,
  а не константы, и взносы с налогами считаются верно.
  """
  use Pulse.DataCase, async: true

  import Pulse.Factory

  alias Pulse.Payroll.Calculator

  # Ориентиры на 2026 год из значений по умолчанию.
  @values %{
    "mzp" => Decimal.new("85000"),
    "mrp" => Decimal.new("4325"),
    "opv" => Decimal.new("10"),
    "vosms" => Decimal.new("2"),
    "ipn" => Decimal.new("10"),
    "so" => Decimal.new("3.5"),
    "opvr" => Decimal.new("1.5"),
    "oosms" => Decimal.new("3"),
    "deduction_monthly" => Decimal.new("30"),
    "opv_cap_mzp" => Decimal.new("50"),
    "so_cap_mzp" => Decimal.new("7"),
    "oosms_cap_mzp" => Decimal.new("10"),
    "opvr_cap_mzp" => Decimal.new("50")
  }

  describe "расчёт по окладу" do
    test "200 000 тенге: удержания и взносы" do
      result = Calculator.calculate_with_values(Decimal.new("200000"), @values)

      # ОПВ 10 % = 20 000; ВОСМС 2 % = 4 000.
      assert Decimal.equal?(result.opv, Decimal.new("20000"))
      assert Decimal.equal?(result.vosms, Decimal.new("4000"))

      # Вычет 30 МРП = 129 750; база ИПН = 200 000 − 20 000 − 4 000 − 129 750 = 46 250.
      # ИПН 10 % = 4 625.
      assert Decimal.equal?(result.ipn, Decimal.new("4625"))

      # Работодатель: СО 3.5 % от (200 000 − 20 000) = 6 300; ОПВР 1.5 % = 3 000;
      # ООСМС 3 % = 6 000.
      assert Decimal.equal?(result.so, Decimal.new("6300"))
      assert Decimal.equal?(result.opvr, Decimal.new("3000"))
      assert Decimal.equal?(result.oosms, Decimal.new("6000"))

      # На руки: 200 000 − (20 000 + 4 000 + 4 625) = 171 375.
      assert Decimal.equal?(result.net, Decimal.new("171375"))
    end

    test "доход ниже вычета: ИПН равен нулю" do
      result = Calculator.calculate_with_values(Decimal.new("100000"), @values)

      # 100 000 − 10 000 − 2 000 − 129 750 < 0 → ИПН 0.
      assert Decimal.equal?(result.ipn, Decimal.new("0"))
      assert Decimal.equal?(result.opv, Decimal.new("10000"))
      assert Decimal.equal?(result.net, Decimal.new("88000"))
    end

    test "верхние границы базы взносов применяются" do
      # Оклад 6 000 000: база ОПВ ограничена 50 МЗП = 4 250 000,
      # база СО — 7 МЗП = 595 000, база ООСМС — 10 МЗП = 850 000.
      result = Calculator.calculate_with_values(Decimal.new("6000000"), @values)

      assert Decimal.equal?(result.opv, Decimal.new("425000"))
      assert Decimal.equal?(result.so, Decimal.new("20825"))
      assert Decimal.equal?(result.oosms, Decimal.new("25500"))
    end
  end

  describe "параметры на дату" do
    test "считает по values из statutory_rates" do
      seed_statutory_rates!()

      gross = Decimal.new("200000")

      assert {:ok, result} =
               Calculator.calculate(gross, rates_map(~D[2026-06-01]), ~D[2026-06-01])

      assert Decimal.equal?(result.gross, gross)
      assert Decimal.equal?(result.opv, Decimal.new("20000"))
      assert Decimal.equal?(result.ipn, Decimal.new("4625"))
    end

    test "ставка на дату берётся из периода действия" do
      seed_statutory_rates!()

      # Меняем ставку ИПН с 2026-07-01 — расчёт на август берёт новую,
      # на май — прежнюю.
      create_statutory_rate(%{
        code: "ipn",
        value: Decimal.new("5"),
        valid_from: ~D[2026-07-01]
      })

      assert {:ok, august} = Calculator.rates_on(~D[2026-08-01])
      assert Decimal.equal?(august["ipn"], Decimal.new("5"))

      assert {:ok, may} = Calculator.rates_on(~D[2026-05-01])
      assert Decimal.equal?(may["ipn"], Decimal.new("10"))
    end

    test "без обязательного параметра — явная ошибка" do
      assert {:error, message} = Calculator.rates_on(~D[2026-06-01])
      assert message =~ "не задан параметр"
    end
  end

  defp rates_map(date) do
    {:ok, rates} = Calculator.rates_on(date)
    rates
  end
end
