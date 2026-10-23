defmodule Pulse.Accounting.Account do
  @moduledoc """
  Счёт плана счетов (раздел 5.4 ТЗ).

  Вид счёта определяет, как читается сальдо: у активного остаток
  дебетовый, у пассивного — кредитовый, у активно-пассивного сальдо
  может быть с любой стороны. Забалансовые счета не входят в баланс.

  Валютный и количественный учёт — признаки счёта: по ним проводки
  обязаны нести валюту или количество.
  """
  use Pulse.Accounting.Resource,
    domain: Pulse.Accounting,
    table: "accounts"

  @kinds [:active, :passive, :active_passive]

  actions do
    create :create do
      accept([
        :code,
        :name,
        :kind,
        :off_balance,
        :currency,
        :quantity,
        :subaccount_codes,
        :parent_code
      ])

      validate(present([:code, :name, :kind]))
      validate(one_of(:kind, @kinds))
    end

    update :update do
      accept([
        :name,
        :kind,
        :off_balance,
        :currency,
        :quantity,
        :subaccount_codes,
        :parent_code
      ])

      validate(one_of(:kind, @kinds))
    end
  end

  attributes do
    # Код счёта по типовому плану РК: «1030», «1330», «3310».
    attribute :code, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :name, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :kind, :atom do
      allow_nil?(false)
      default(:active)
      constraints(one_of: [:active, :passive, :active_passive])
      public?(true)
    end

    attribute :off_balance, :boolean do
      allow_nil?(false)
      default(false)
      public?(true)
    end

    attribute :currency, :boolean do
      allow_nil?(false)
      default(false)
      public?(true)
    end

    attribute :quantity, :boolean do
      allow_nil?(false)
      default(false)
      public?(true)
    end

    # Коды видов субконто: до трёх разрезов аналитики на счёт.
    attribute :subaccount_codes, {:array, :string} do
      allow_nil?(false)
      default([])
      public?(true)
      constraints(max_length: 3)
    end

    # Код счёта-родителя: «1030» → «1031» в типовом плане.
    attribute :parent_code, :string do
      allow_nil?(true)
      public?(true)
    end
  end

  identities do
    identity(:unique_code, [:code])
  end
end
