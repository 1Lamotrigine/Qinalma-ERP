defmodule Pulse.Tax.RatesTest do
  @moduledoc """
  Законодательные параметры (этап 7).

  Критерий этапа: ставки и пороги хранятся с датами действия и
  выбираются на дату, а не зашиты в код.
  """
  use Pulse.DataCase, async: true

  import Pulse.Factory

  alias Pulse.Tax.Rates

  describe "выбор значения на дату" do
    test "находит действующее значение" do
      create_statutory_rate(%{
        code: "vat_rate",
        value: Decimal.new("16"),
        valid_from: ~D[2026-01-01]
      })

      assert {:ok, rate} = Rates.fetch("vat_rate", ~D[2026-06-01])
      assert Decimal.equal?(rate.value, Decimal.new("16"))
      assert rate.valid_from == ~D[2026-01-01]
    end

    test "берёт последнее значение, начавшееся до даты" do
      create_statutory_rate(%{
        code: "vat_rate",
        value: Decimal.new("12"),
        valid_from: ~D[2026-01-01]
      })

      create_statutory_rate(%{
        code: "vat_rate",
        value: Decimal.new("16"),
        valid_from: ~D[2026-07-01]
      })

      assert {:ok, rate} = Rates.fetch("vat_rate", ~D[2026-08-01])
      assert Decimal.equal?(rate.value, Decimal.new("16"))

      assert {:ok, older} = Rates.fetch("vat_rate", ~D[2026-03-01])
      assert Decimal.equal?(older.value, Decimal.new("12"))
    end

    test "истёкшее значение не используется" do
      create_statutory_rate(%{
        code: "vat_rate",
        value: Decimal.new("12"),
        valid_from: ~D[2026-01-01],
        valid_to: ~D[2026-06-30]
      })

      assert {:error, message} = Rates.fetch("vat_rate", ~D[2026-09-01])
      assert message =~ "истекло"
    end

    test "незнакомый код — явная ошибка, а не значение по умолчанию" do
      assert {:error, message} = Rates.fetch("unknown_code", ~D[2026-06-01])
      assert message =~ "не задано значение"
    end

    test "get/2 возвращает nil вместо ошибки" do
      assert Rates.get("unknown_code", ~D[2026-06-01]) == nil
    end
  end

  describe "ставка НДС в долях" do
    test "проценты переводятся в доли единицы" do
      create_statutory_rate(%{
        code: "vat_rate",
        value: Decimal.new("16"),
        valid_from: ~D[2026-01-01]
      })

      assert {:ok, share} = Rates.vat_share(~D[2026-06-01])
      assert Decimal.equal?(share, Decimal.new("0.16"))
    end
  end

  describe "значения по умолчанию" do
    test "загружаются и читаются на 2026 год" do
      seed_statutory_rates!()

      assert {:ok, rate} = Rates.fetch("mrp", ~D[2026-06-01])
      assert Decimal.compare(rate.value, 0) == :gt

      assert {:ok, vat} = Rates.fetch("vat_rate", ~D[2026-06-01])
      assert Decimal.equal?(vat.value, Decimal.new("16"))
    end

    test "current/1 даёт одно значение на код" do
      seed_statutory_rates!()

      current = Rates.current(~D[2026-06-01])
      codes = Enum.map(current, & &1.code)

      assert "vat_rate" in codes
      assert length(codes) == length(Enum.uniq(codes))
    end
  end
end
