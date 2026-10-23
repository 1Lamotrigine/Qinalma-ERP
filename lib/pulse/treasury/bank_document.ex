defmodule Pulse.Treasury.BankDocument do
  @moduledoc """
  Банковский расчётный документ: поступление или списание по счёту.

  Один документ покрывает и платёжное поручение, и поступление:
  направление задаётся `direction`. Проведение пишет движение денег,
  проводку и — при расчётах с контрагентом — движение взаиморасчётов.
  """
  use Pulse.Accounting.Document,
    domain: Pulse.Treasury,
    table: "bank_documents",
    create_accept: [
      :doc_date,
      :number,
      :currency_id,
      :rate,
      :comment,
      :direction,
      :bank_account_id,
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
      :bank_account_id,
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
    # Поступление на счёт или списание со счёта.
    attribute :direction, :atom do
      allow_nil?(false)
      default(:receipt)
      constraints(one_of: [:receipt, :expense])
      public?(true)
    end

    attribute :bank_account_id, :uuid do
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
    belongs_to :bank_account, Pulse.Treasury.BankAccount do
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
