defmodule Pulse.Treasury.BankAccount do
  @moduledoc """
  Банковский счёт организации.

  Номер счёта уникален в пределах организации. Счёт участвует
  в движениях денег как источник или получатель средств.
  """
  use Pulse.Catalog.Resource, domain: Pulse.Treasury, table: "bank_accounts"

  actions do
    create :create do
      accept([:name, :account_number, :bank_id, :currency_id, :comment])
      validate(present([:name, :account_number]))
    end

    update :update do
      accept([:name, :account_number, :bank_id, :currency_id, :comment])
    end
  end

  attributes do
    attribute :name, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :account_number, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :comment, :string do
      allow_nil?(true)
      public?(true)
    end
  end

  relationships do
    belongs_to :bank, Pulse.Catalog.Bank do
      attribute_writable?(true)
      public?(true)
    end

    belongs_to :currency, Pulse.Catalog.Currency do
      attribute_writable?(true)
      public?(true)
    end
  end

  identities do
    identity(:unique_account_number, [:account_number])
  end
end
