defmodule Pulse.Ledger.CashMovement do
  @moduledoc """
  Движение денежных средств: касса или банковский счёт (раздел 5.2 ТЗ).

  Хранит, куда пришли или откуда ушли деньги, по какой статье
  и на какую сумму. Остаток по кассе или счёту — сумма движений.
  """
  use Pulse.Ledger.Resource, table: "cash_movements", domain: Pulse.Ledger

  postgres do
    custom_indexes do
      # Остатки денег читаются по счёту или кассе за период.
      index([:organization_id, :account_kind, :account_id, :period],
        name: "cash_movements_balance_index"
      )

      index([:organization_id, :document_type, :document_id],
        name: "cash_movements_document_index"
      )
    end
  end

  attributes do
    # Куда отнести движение: касса или банковский счёт.
    attribute :account_kind, :atom do
      allow_nil?(false)
      constraints(one_of: [:cash, :bank])
      public?(true)
    end

    attribute :account_id, :uuid do
      allow_nil?(false)
      public?(true)
    end

    # Поступление или выдача денег.
    attribute :record_type, :atom do
      allow_nil?(false)
      constraints(one_of: [:receipt, :expense])
      public?(true)
    end

    attribute :period, :date do
      allow_nil?(false)
      public?(true)
    end

    attribute :doc_date, :date do
      allow_nil?(false)
      public?(true)
    end

    attribute :amount, :decimal do
      allow_nil?(false)
      public?(true)
    end

    # Валюта и сумма в валюте — для валютных касс и счетов.
    attribute :currency_id, :uuid do
      allow_nil?(true)
      public?(true)
    end

    attribute :amount_currency, :decimal do
      allow_nil?(true)
      public?(true)
    end

    # Статья движения денежных средств.
    attribute :cash_flow_item_id, :uuid do
      allow_nil?(true)
      public?(true)
    end

    # Контрагент и договор — для взаиморасчётов и отчётов по деньгам.
    attribute :counterparty_id, :uuid do
      allow_nil?(true)
      public?(true)
    end

    attribute :contract_id, :uuid do
      allow_nil?(true)
      public?(true)
    end
  end

  actions do
    create :create do
      accept([
        :organization_id,
        :document_type,
        :document_id,
        :document_line_id,
        :account_kind,
        :account_id,
        :record_type,
        :period,
        :doc_date,
        :amount,
        :currency_id,
        :amount_currency,
        :cash_flow_item_id,
        :counterparty_id,
        :contract_id
      ])
    end
  end
end
