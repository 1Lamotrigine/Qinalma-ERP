defmodule Pulse.Sales.Shipment do
  @moduledoc """
  Реализация ТМЗ и услуг.

  Расходует товары со склада по средней себестоимости; цена продажи
  хранится в строках отдельно от себестоимости.
  """
  use Pulse.Accounting.Document,
    domain: Pulse.Sales,
    table: "sales_shipments",
    create_accept: [
      :doc_date,
      :number,
      :currency_id,
      :rate,
      :comment,
      :counterparty_id,
      :contract_id,
      :warehouse_id
    ],
    update_accept: [
      :doc_date,
      :number,
      :currency_id,
      :rate,
      :comment,
      :counterparty_id,
      :contract_id,
      :warehouse_id
    ]

  actions do
    update :post do
      accept([])
      require_atomic?(false)
      change({Pulse.Accounting.Changes.Post, rule: Pulse.Posting.SalesShipment})
    end

    update :unpost do
      accept([])
      require_atomic?(false)
      change({Pulse.Accounting.Changes.Unpost, rule: Pulse.Posting.SalesShipment})
    end

    # Служебные действия: статус меняет только проведение, права
    # проверяются на уровне `:post` и `:unpost`.
    update :mark_posted do
      accept([:status, :posted_at, :posted_by])
      require_atomic?(false)
    end

    update :mark_draft do
      accept([:status, :posted_at, :posted_by])
      require_atomic?(false)
    end
  end

  attributes do
    attribute :counterparty_id, :uuid do
      allow_nil?(false)
      public?(true)
    end

    # Договор — разрез взаиморасчётов с контрагентом.
    attribute :contract_id, :uuid do
      allow_nil?(true)
      public?(true)
    end

    attribute :warehouse_id, :uuid do
      allow_nil?(false)
      public?(true)
    end
  end

  relationships do
    belongs_to :counterparty, Pulse.Catalog.Counterparty do
      define_attribute?(false)
      public?(true)
    end

    belongs_to :warehouse, Pulse.Catalog.Warehouse do
      define_attribute?(false)
      public?(true)
    end

    has_many :lines, Pulse.Sales.ShipmentLine do
      destination_attribute(:document_id)
      public?(true)
      sort(line_no: :asc)
    end
  end
end
