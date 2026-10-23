defmodule Pulse.Ledger.PayrollMovement do
  @moduledoc """
  Регистр накопления по расчётам с работниками (раздел 5.5 ТЗ).

  Движение фиксирует начисление или удержание по сотруднику: сумма с
  разрезом «вид» (начислено, ОПВ, ВОСМС, ИПН, СО, ОПВР, ООСМС, выплата).
  Отсюда строятся расчётные ведомости, листки и свод по взносам.

  Регистр мультитенантный и только дополняется: движения создаются
  проведением документа-регистратора, а удаляются его отменой.
  """
  use Pulse.Ledger.Resource, table: "ledger_payroll_movements"

  @kinds ~w(gross opv vosms ipn so opvr oosms payment)a

  actions do
    create :create do
      accept([
        :organization_id,
        :document_type,
        :document_id,
        :document_line_id,
        :employee_id,
        :kind,
        :period,
        :doc_date,
        :amount,
        :currency_id,
        :amount_currency
      ])

      validate(present([:employee_id, :kind, :amount]))
    end
  end

  attributes do
    attribute :employee_id, :uuid do
      allow_nil?(false)
      public?(true)
    end

    attribute :kind, :atom do
      allow_nil?(false)
      constraints(one_of: @kinds)
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
  end

  @doc """
  Известные виды движений по зарплате.
  """
  @spec kinds() :: [atom()]
  def kinds, do: @kinds
end
