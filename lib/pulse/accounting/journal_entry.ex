defmodule Pulse.Accounting.JournalEntry do
  @moduledoc """
  Проводка журнала (раздел 5.2 ТЗ).

  Проводка только добавляется: её создаёт проведение документа, удаляет
  отмена. Прямая запись в таблицу запрещена — API `Pulse.Accounting.Entries`.

  Субконто хранятся по сторонам проводки: до трёх разрезов на дебет
  и до трёх на кредит. Каждый разрез — пара «вид субконто + значение».

  Поле `ledger` разделяет бухгалтерский и налоговый учёт: одна и та же
  операция может дать две проводки с разными счетами.
  """
  use Ash.Resource,
    otp_app: :pulse,
    domain: Pulse.Accounting,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table("journal_entries")
    repo(Pulse.Repo)

    custom_indexes do
      # ОСВ и главная книга читают проводки организации за период.
      index([:organization_id, :period, :debit_account_code],
        name: "journal_entries_debit_index"
      )

      index([:organization_id, :period, :credit_account_code],
        name: "journal_entries_credit_index"
      )

      index([:organization_id, :document_type, :document_id],
        name: "journal_entries_document_index"
      )
    end
  end

  multitenancy do
    strategy(:attribute)
    attribute(:organization_id)
  end

  policies do
    policy action_type([:read, :create, :destroy]) do
      authorize_if(Pulse.Core.Checks.RoleAllowed)
    end

    policy action_type(:destroy) do
      authorize_if(Pulse.Ledger.Checks.SameOrganization)
    end
  end

  actions do
    default_accept([:organization_id])
    defaults([:read])

    create :create do
      accept([
        :organization_id,
        :period,
        :doc_date,
        :document_type,
        :document_id,
        :ledger,
        :debit_account_code,
        :credit_account_code,
        :amount,
        :currency_code,
        :amount_currency,
        :quantity,
        :content,
        :debit_subaccounts,
        :credit_subaccounts
      ])

      validate(present([:debit_account_code, :credit_account_code, :amount]))
    end

    # Удаление проводок при отмене проведения.
    destroy :purge do
      primary?(false)
      accept([])
      require_atomic?(false)
    end
  end

  attributes do
    uuid_v7_primary_key(:id)

    attribute :organization_id, :uuid do
      allow_nil?(false)
      public?(true)
    end

    # Документ-основание и его тип (`purchasing.receipt`).
    attribute :document_type, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :document_id, :uuid do
      allow_nil?(false)
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

    attribute :ledger, :atom do
      allow_nil?(false)
      default(:accounting)
      constraints(one_of: [:accounting, :tax])
      public?(true)
    end

    attribute :debit_account_code, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :credit_account_code, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :amount, :decimal do
      allow_nil?(false)
      public?(true)
    end

    attribute :currency_code, :string do
      allow_nil?(true)
      public?(true)
    end

    attribute :amount_currency, :decimal do
      allow_nil?(true)
      public?(true)
    end

    attribute :quantity, :decimal do
      allow_nil?(true)
      public?(true)
    end

    # Содержание проводки — текст операции для карточки и главной книги.
    attribute :content, :string do
      allow_nil?(true)
      public?(true)
    end

    # `[%{"type" => "counterparty", "id" => uuid}, ...]`, до трёх.
    attribute :debit_subaccounts, {:array, :map} do
      allow_nil?(false)
      default([])
      public?(true)
    end

    attribute :credit_subaccounts, {:array, :map} do
      allow_nil?(false)
      default([])
      public?(true)
    end

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end
end
