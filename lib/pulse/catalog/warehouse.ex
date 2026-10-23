defmodule Pulse.Catalog.Warehouse do
  @moduledoc """
  Склад (место хранения).

  Код уникален в пределах организации.
  """
  use Pulse.Catalog.Resource, table: "warehouses"

  actions do
    create :create do
      accept([:code, :name, :address, :comment])
      validate(present(:name))
    end

    update :update do
      accept([:code, :name, :address, :comment])
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

    attribute :address, :string do
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
