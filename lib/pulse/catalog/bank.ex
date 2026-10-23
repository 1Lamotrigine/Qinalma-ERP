defmodule Pulse.Catalog.Bank do
  @moduledoc """
  Банк: БИК и наименование.

  БИК проверяется на формат Казахстана — 12 символов; уникален
  в пределах организации.
  """
  use Pulse.Catalog.Resource, table: "banks"

  actions do
    create :create do
      accept([:bic, :name, :bank_name, :mfo, :address])
      validate(present([:bic, :name]))
    end

    update :update do
      accept([:bic, :name, :bank_name, :mfo, :address])
    end
  end

  validations do
    validate(
      {Ash.Resource.Validation.Match,
       attribute: :bic, match: ~r/^\d{12}$/, message: "БИК должен содержать 12 цифр"}
    )
  end

  attributes do
    attribute :bic, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :name, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :bank_name, :string do
      allow_nil?(true)
      public?(true)
    end

    attribute :mfo, :string do
      allow_nil?(true)
      public?(true)
    end

    attribute :address, :string do
      allow_nil?(true)
      public?(true)
    end
  end

  identities do
    identity(:unique_bic, [:bic])
  end
end
