defmodule Pulse.Catalog.Currency do
  @moduledoc """
  Валюта: код ISO 4217, курс и дата курса.

  Код уникален в пределах организации.
  """
  use Pulse.Catalog.Resource, table: "currencies"

  actions do
    create :create do
      accept([:code, :name, :rate, :rate_date, :base])
      validate(present([:code, :name]))
    end

    update :update do
      accept([:code, :name, :rate, :rate_date, :base])
    end
  end

  attributes do
    attribute :code, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :name, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :rate, :decimal do
      allow_nil?(false)
      default(Decimal.new(1))
      public?(true)
    end

    attribute :rate_date, :date do
      allow_nil?(true)
      public?(true)
    end

    attribute :base, :boolean do
      allow_nil?(false)
      default(false)
      public?(true)
    end
  end

  identities do
    identity(:unique_code, [:code])
  end
end
