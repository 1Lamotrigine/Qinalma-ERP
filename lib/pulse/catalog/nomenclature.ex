defmodule Pulse.Catalog.Nomenclature do
  @moduledoc """
  Номенклатура: товар, услуга или работа.

  Код уникален в пределах организации; цена — Decimal.
  """
  use Pulse.Catalog.Resource, table: "nomenclature"

  actions do
    create :create do
      accept([:code, :name, :kind, :unit_id, :price, :vat_rate, :comment])
      validate(present([:name, :kind]))
    end

    update :update do
      accept([:code, :name, :kind, :unit_id, :price, :vat_rate, :comment])
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
      default(:product)
      constraints(one_of: [:product, :service, :work])
      public?(true)
    end

    attribute :price, :decimal do
      allow_nil?(true)
      public?(true)
    end

    attribute :vat_rate, :atom do
      allow_nil?(true)
      constraints(one_of: [:none, :ten, :twelve])
      public?(true)
    end

    attribute :comment, :string do
      allow_nil?(true)
      public?(true)
    end
  end

  relationships do
    belongs_to :unit, Pulse.Catalog.Unit do
      attribute_writable?(true)
      public?(true)
    end
  end

  identities do
    identity(:unique_code, [:code])
  end
end
