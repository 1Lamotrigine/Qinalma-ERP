defmodule Pulse.Ledger.SettlementMovement do
  @moduledoc """
  Движение взаиморасчётов по паре «контрагент + договор» (раздел 5.6 ТЗ).

  Направление движения:

    * `:debt` — выросла дебиторская задолженность контрагента
      (мы отгрузили, нам должны);
    * `:credit` — выросла кредиторская задолженность (нам поставили,
      мы должны);
    * `:payment` — поступила оплата: закрывает дебиторскую задолженность;
    * `:offset` — зачёт аванса: закрывает встречную задолженность.

  Задолженность контрагента = сумма `:debt` минус `:payment` и `:offset`
  по дебиторской стороне; кредиторская — по кредитовой.
  """
  use Pulse.Ledger.Resource, table: "settlement_movements", domain: Pulse.Ledger

  postgres do
    custom_indexes do
      # Долги читаются по контрагенту и договору.
      index([:organization_id, :counterparty_id, :contract_id],
        name: "settlement_movements_counterparty_index"
      )

      index([:organization_id, :document_type, :document_id],
        name: "settlement_movements_document_index"
      )
    end
  end

  attributes do
    attribute :counterparty_id, :uuid do
      allow_nil?(false)
      public?(true)
    end

    attribute :contract_id, :uuid do
      allow_nil?(true)
      public?(true)
    end

    # Направление: долг, оплата или зачёт аванса.
    attribute :direction, :atom do
      allow_nil?(false)
      constraints(one_of: [:debt, :credit, :payment, :offset])
      public?(true)
    end

    # Сторона расчётов: нам должны (дебиторская) или мы должны.
    attribute :side, :atom do
      allow_nil?(false)
      constraints(one_of: [:debit, :credit])
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

    attribute :currency_id, :uuid do
      allow_nil?(true)
      public?(true)
    end

    attribute :amount_currency, :decimal do
      allow_nil?(true)
      public?(true)
    end

    # Срок оплаты из договора или счёта — для просроченной задолженности.
    attribute :due_date, :date do
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
        :counterparty_id,
        :contract_id,
        :direction,
        :side,
        :period,
        :doc_date,
        :amount,
        :currency_id,
        :amount_currency,
        :due_date
      ])
    end
  end
end
