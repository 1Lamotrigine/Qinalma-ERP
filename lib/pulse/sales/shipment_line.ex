defmodule Pulse.Sales.ShipmentLine do
  @moduledoc """
  Строка реализации: номенклатура, количество, цена продажи и сумма.
  """
  use Pulse.Accounting.DocumentLine,
    domain: Pulse.Sales,
    table: "sales_shipment_lines"

  attributes do
    attribute :nomenclature_id, :uuid do
      allow_nil?(false)
      public?(true)
    end
  end

  relationships do
    belongs_to :document, Pulse.Sales.Shipment do
      define_attribute?(false)
      public?(true)
    end

    belongs_to :nomenclature, Pulse.Catalog.Nomenclature do
      define_attribute?(false)
      public?(true)
    end
  end
end
