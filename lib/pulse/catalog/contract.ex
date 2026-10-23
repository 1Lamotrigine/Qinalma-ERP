defmodule Pulse.Catalog.Contract do
  @moduledoc """
  Договор контрагента: номер, срок действия и сумма в валюте договора.
  """
  use Pulse.Catalog.Resource, table: "contracts"

  actions do
    create :create do
      accept([:number, :name, :counterparty_id, :currency_id, :amount, :valid_from, :valid_to])
      validate(present([:number, :counterparty_id]))
    end

    update :update do
      accept([:number, :name, :counterparty_id, :currency_id, :amount, :valid_from, :valid_to])
    end
  end

  attributes do
    attribute :number, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :name, :string do
      allow_nil?(true)
      public?(true)
    end

    attribute :amount, :decimal do
      allow_nil?(true)
      public?(true)
    end

    attribute :valid_from, :date do
      allow_nil?(true)
      public?(true)
    end

    attribute :valid_to, :date do
      allow_nil?(true)
      public?(true)
    end
  end

  relationships do
    belongs_to :counterparty, Pulse.Catalog.Counterparty do
      allow_nil?(false)
      attribute_writable?(true)
      public?(true)
    end

    belongs_to :currency, Pulse.Catalog.Currency do
      attribute_writable?(true)
      public?(true)
    end
  end
end
