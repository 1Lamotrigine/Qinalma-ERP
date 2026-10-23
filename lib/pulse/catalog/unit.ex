defmodule Pulse.Catalog.Unit do
  @moduledoc """
  Единица измерения (классификатор ЕИ).

  Код уникален в пределах организации.
  """
  use Pulse.Catalog.Resource, table: "units"

  actions do
    create :create do
      accept([:code, :name, :designation])
      validate(present([:code, :name]))
    end

    update :update do
      accept([:code, :name, :designation])
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

    attribute :designation, :string do
      allow_nil?(true)
      public?(true)
    end
  end

  identities do
    identity(:unique_code, [:code])
  end
end
