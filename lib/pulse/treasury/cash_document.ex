defmodule Pulse.Treasury.CashDocument do
  @moduledoc """
  Кассовый документ: приходный или расходный кассовый ордер.

  Приходует или выдаёт наличные из кассы. Проведение пишет движение
  денег, проводку и — при расчётах с контрагентом — движение
  взаиморасчётов.
  """
  use Pulse.Accounting.Document,
    domain: Pulse.Treasury,
    table: "cash_documents",
    create_accept: [
      :doc_date,
      :number,
      :currency_id,
      :rate,
      :comment,
      :direction,
      :cash_desk_id,
      :counterparty_id,
      :contract_id,
      :cash_flow_item_id,
      :amount
    ],
    update_accept: [
      :doc_date,
      :number,
      :currency_id,
      :rate,
      :comment,
      :direction,
      :cash_desk_id,
      :counterparty_id,
      :contract_id,
      :cash_flow_item_id,
      :amount
    ]

  actions do
    update :post do
      accept([])
      require_atomic?(false)
      change({Pulse.Accounting.Changes.Post, rule: Pulse.Posting.TreasuryPayment})
    end

    update :unpost do
      accept([])
      require_atomic?(false)
      change({Pulse.Accounting.Changes.Unpost, rule: Pulse.Posting.TreasuryPayment})
    end

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
    attribute :direction, :atom do
      allow_nil?(false)
      default(:receipt)
      constraints(one_of: [:receipt, :expense])
      public?(true)
    end

    attribute :cash_desk_id, :uuid do
      allow_nil?(false)
      public?(true)
    end

    attribute :counterparty_id, :uuid do
      allow_nil?(true)
      public?(true)
    end

    attribute :contract_id, :uuid do
      allow_nil?(true)
      public?(true)
    end

    attribute :cash_flow_item_id, :uuid do
      allow_nil?(true)
      public?(true)
    end

    attribute :amount, :decimal do
      allow_nil?(false)
      default(Decimal.new(0))
      public?(true)
    end
  end

  relationships do
    belongs_to :cash_desk, Pulse.Treasury.CashDesk do
      define_attribute?(false)
      public?(true)
    end

    belongs_to :counterparty, Pulse.Catalog.Counterparty do
      define_attribute?(false)
      public?(true)
    end

    belongs_to :cash_flow_item, Pulse.Treasury.CashFlowItem do
      define_attribute?(false)
      public?(true)
    end
  end

  validations do
    validate(compare(:amount, greater_than: 0), message: "сумма должна быть больше нуля")
  end
end
