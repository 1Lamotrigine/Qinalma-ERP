defmodule Pulse.Payroll.PaymentStatement do
  @moduledoc """
  Ведомость на выплату заработной платы (раздел 5.5 ТЗ).

  Выплата идёт через банк или кассу: документ ссылается на банковский
  счёт либо кассу и на расчётную ведомость. Проведение списывает деньги,
  пишет движение регистра зарплаты (`payment`) и проводку
  Дт 3350 Кт 1030/1010 (`Pulse.Posting.PayrollPayment`).
  """
  use Pulse.Accounting.Document,
    domain: Pulse.Payroll,
    table: "payroll_payments",
    create_accept: [
      :doc_date,
      :number,
      :currency_id,
      :rate,
      :comment,
      :accrual_id,
      :account_kind,
      :bank_account_id,
      :cash_desk_id,
      :amount
    ],
    update_accept: [
      :doc_date,
      :number,
      :currency_id,
      :rate,
      :comment,
      :accrual_id,
      :account_kind,
      :bank_account_id,
      :cash_desk_id,
      :amount
    ]

  actions do
    update :post do
      accept([])
      require_atomic?(false)
      change({Pulse.Accounting.Changes.Post, rule: Pulse.Posting.PayrollPayment})
    end

    update :unpost do
      accept([])
      require_atomic?(false)
      change({Pulse.Accounting.Changes.Unpost, rule: Pulse.Posting.PayrollPayment})
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
    # Расчётная ведомость, по которой выплачивается зарплата.
    attribute :accrual_id, :uuid do
      allow_nil?(true)
      public?(true)
    end

    # Откуда платим: банковский счёт или касса.
    attribute :account_kind, :atom do
      allow_nil?(false)
      default(:bank)
      constraints(one_of: [:bank, :cash])
      public?(true)
    end

    attribute :bank_account_id, :uuid do
      allow_nil?(true)
      public?(true)
    end

    attribute :cash_desk_id, :uuid do
      allow_nil?(true)
      public?(true)
    end

    attribute :amount, :decimal do
      allow_nil?(false)
      public?(true)
    end
  end

  relationships do
    belongs_to :accrual, Pulse.Payroll.Accrual do
      define_attribute?(false)
      public?(true)
    end

    belongs_to :bank_account, Pulse.Treasury.BankAccount do
      define_attribute?(false)
      public?(true)
    end

    belongs_to :cash_desk, Pulse.Treasury.CashDesk do
      define_attribute?(false)
      public?(true)
    end
  end

  @doc """
  Счёт списания документа: банковский счёт или касса.
  """
  @spec account_id(t()) :: String.t() | nil
  def account_id(%{account_kind: :bank, bank_account_id: id}), do: id
  def account_id(%{account_kind: :cash, cash_desk_id: id}), do: id
  def account_id(_statement), do: nil
end
