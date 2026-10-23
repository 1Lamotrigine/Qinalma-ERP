defmodule Pulse.Treasury.CashFlowItem do
  @moduledoc """
  Статья движения денежных средств.

  Определяет вид оборота: поступление или выдача, и на какой счёт
  бухгалтерского учёта относится операция. Статьи — данные: бухгалтер
  добавляет свои без релиза.
  """
  use Pulse.Catalog.Resource, domain: Pulse.Treasury, table: "cash_flow_items"

  actions do
    create :create do
      accept([:code, :name, :kind, :account_code, :comment])
      validate(present([:name, :kind]))
      validate(one_of(:kind, [:receipt, :expense]))
    end

    update :update do
      accept([:code, :name, :kind, :account_code, :comment])
      validate(one_of(:kind, [:receipt, :expense]))
    end
  end

  attributes do
    attribute :code, :string do
      allow_nil?(true)
      public?(true)
    end

    attribute :name, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :kind, :atom do
      allow_nil?(false)
      constraints(one_of: [:receipt, :expense])
      public?(true)
    end

    # Счёт учёта, с которым корреспондирует операция.
    attribute :account_code, :string do
      allow_nil?(true)
      public?(true)
    end

    attribute :comment, :string do
      allow_nil?(true)
      public?(true)
    end
  end

  identities do
    identity(:unique_code, [:code])
  end
end
