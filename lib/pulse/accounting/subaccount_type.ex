defmodule Pulse.Accounting.SubaccountType do
  @moduledoc """
  Вид субконто — разрез аналитики на счетах (контрагенты, номенклатура,
  подразделения и т. п.).

  Счёт ссылается на виды субконто по коду: до трёх аналитических
  разрезов на счёт (раздел 5.4 ТЗ).
  """
  use Pulse.Accounting.Resource,
    domain: Pulse.Accounting,
    table: "subaccount_types"

  actions do
    create :create do
      accept([:code, :name, :reference])
      validate(present([:code, :name]))
    end

    update :update do
      accept([:code, :name, :reference])
    end
  end

  attributes do
    # Код вида субконто: «Контрагенты», «Номенклатура» и т. п.
    attribute :code, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :name, :string do
      allow_nil?(false)
      public?(true)
    end

    # На какой справочник ссылается аналитика: `catalog.counterparty`,
    # `catalog.nomenclature`, `core.department`. Данные, а не код.
    attribute :reference, :string do
      allow_nil?(true)
      public?(true)
    end
  end

  identities do
    identity(:unique_code, [:code])
  end
end
