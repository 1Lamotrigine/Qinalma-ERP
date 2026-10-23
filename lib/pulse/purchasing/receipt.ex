defmodule Pulse.Purchasing.Receipt do
  @moduledoc """
  Поступление ТМЗ и услуг.

  Приходует товары на склад: движения `:receipt` по строкам, сумма
  строки — количество × цена. Проведение и отмена — общие
  (`Pulse.Accounting.Posting`), правила расчёта — в
  `Pulse.Posting.PurchasingReceipt`.
  """
  use Pulse.Accounting.Document,
    domain: Pulse.Purchasing,
    table: "purchasing_receipts",
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
    # Проведение и отмена: движения, статус и аудит — в одной транзакции.
    update :post do
      accept([])
      require_atomic?(false)
      change({Pulse.Accounting.Changes.Post, rule: Pulse.Posting.PurchasingReceipt})
    end

    update :unpost do
      accept([])
      require_atomic?(false)
      change({Pulse.Accounting.Changes.Unpost, rule: Pulse.Posting.PurchasingReceipt})
    end

    # Служебные действия: статус меняет только проведение.
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

    has_many :lines, Pulse.Purchasing.ReceiptLine do
      destination_attribute(:document_id)
      public?(true)
      sort(line_no: :asc)
    end
  end
end
