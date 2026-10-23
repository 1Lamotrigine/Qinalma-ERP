defmodule Pulse.Sales do
  @moduledoc """
  Домен продаж: реализации ТМЗ и услуг.
  """
  use Ash.Domain, otp_app: :pulse, extensions: [AshPaperTrail.Domain]

  resources do
    resource Pulse.Sales.Shipment do
      define(:list_shipments, action: :read)
    end

    resource Pulse.Sales.ShipmentLine do
      define(:list_shipment_lines, action: :read)
    end

    paper_trail do
      include_versions?(true)
    end
  end
end
