defmodule Pulse.Accounting.EntryTemplate do
  @moduledoc """
  Шаблон проводок — типовая операция (раздел 5.4 ТЗ).

  Шаблон связывает операцию (`kind`) со правилами счетов. Бухгалтер
  меняет счета без релиза: шаблон хранится данными, а не кодом.

  Поля `debit_account_code` и `credit_account_code` поддерживают
  подстановку из операции: например, `"$counterparty"` означает
  счёт из карточки контрагента. Значения по умолчанию — конкретные
  коды типового плана.
  """
  use Pulse.Accounting.Resource,
    domain: Pulse.Accounting,
    table: "entry_templates"

  @kinds [
    :receipt_tmz,
    :shipment_tmz,
    :receipt_service,
    :shipment_service,
    :cash_receipt,
    :cash_payment,
    :bank_receipt,
    :bank_payment,
    :payroll_accrual,
    :payroll_ipn,
    :payroll_opv,
    :payroll_employer,
    :payroll_payment
  ]

  actions do
    create :create do
      accept([
        :kind,
        :name,
        :debit_account_code,
        :credit_account_code,
        :debit_subaccount_codes,
        :credit_subaccount_codes,
        :ledger,
        :note
      ])

      validate(present([:kind, :name, :debit_account_code, :credit_account_code]))
      validate(one_of(:kind, @kinds))
      validate(one_of(:ledger, [:accounting, :tax]))
    end

    update :update do
      accept([
        :name,
        :debit_account_code,
        :credit_account_code,
        :debit_subaccount_codes,
        :credit_subaccount_codes,
        :ledger,
        :note
      ])

      validate(one_of(:kind, @kinds))
      validate(one_of(:ledger, [:accounting, :tax]))
    end
  end

  attributes do
    attribute :kind, :atom do
      allow_nil?(false)
      constraints(one_of: @kinds)
      public?(true)
    end

    attribute :name, :string do
      allow_nil?(false)
      public?(true)
    end

    # Коды счетов; допускают подстановку `$...` из документа.
    attribute :debit_account_code, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :credit_account_code, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :debit_subaccount_codes, {:array, :string} do
      allow_nil?(false)
      default([])
      public?(true)
    end

    attribute :credit_subaccount_codes, {:array, :string} do
      allow_nil?(false)
      default([])
      public?(true)
    end

    attribute :ledger, :atom do
      allow_nil?(false)
      default(:accounting)
      constraints(one_of: [:accounting, :tax])
      public?(true)
    end

    attribute :note, :string do
      allow_nil?(true)
      public?(true)
    end
  end

  identities do
    identity(:unique_kind_ledger, [:kind, :ledger])
  end
end
