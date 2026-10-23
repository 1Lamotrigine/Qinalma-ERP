defmodule Pulse.Tax.StatutoryRate do
  @moduledoc """
  Законодательный параметр с датой действия (раздел 5.5 ТЗ).

  Одна строка — одно значение одного кода на период действия: ставка
  НДС, МРП, МЗП, ОПВ, ИПН и прочее. Значение выбирается на дату:
  берётся запись, в чей интервал `valid_from`–`valid_to` попадает дата.

  Параметры общие для инсталляции: закон один для всех организаций.
  """
  use Pulse.Accounting.Resource,
    domain: Pulse.Tax,
    table: "statutory_rates"

  @known_codes ~w(
    vat_rate vat_rate_reduced
    mrp mzp
    opv opvr so vosms oosms ipn
    deduction_monthly deduction_yearly
    opv_cap_mzp so_cap_mzp oosms_cap_mzp opvr_cap_mzp
  )

  actions do
    create :create do
      accept([:code, :name, :value, :valid_from, :valid_to, :note])
      validate(present([:code, :value, :valid_from]))
    end

    update :update do
      accept([:name, :value, :valid_from, :valid_to, :note])
    end
  end

  attributes do
    # Код параметра: `vat_rate`, `mrp`, `opv` и т. п.
    attribute :code, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :name, :string do
      allow_nil?(true)
      public?(true)
    end

    # Значение: ставка в процентах или сумма в тенге.
    attribute :value, :decimal do
      allow_nil?(false)
      public?(true)
    end

    attribute :valid_from, :date do
      allow_nil?(false)
      public?(true)
    end

    # Пусто — действует бессрочно до следующей записи с тем же кодом.
    attribute :valid_to, :date do
      allow_nil?(true)
      public?(true)
    end

    attribute :note, :string do
      allow_nil?(true)
      public?(true)
    end
  end

  identities do
    identity(:unique_code_from, [:code, :valid_from])
  end

  @doc """
  Известные коды параметров — для выпадающих списков в интерфейсе.
  """
  @spec known_codes() :: [String.t()]
  def known_codes, do: @known_codes
end
