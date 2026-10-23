defmodule Pulse.Payroll.AccrualLine do
  @moduledoc """
  Строка расчётной ведомости: расчёт по одному сотруднику.

  Суммы фиксируются на момент расчёта: пересчёт задним числом не
  переписывает уже проведённую ведомость (как и в бухгалтерии —
  изменение параметров закона не имеет обратной силы).
  """
  use Pulse.Accounting.DocumentLine,
    domain: Pulse.Payroll,
    table: "payroll_accrual_lines",
    create_accept: [
      :organization_id,
      :document_id,
      :line_no,
      :employee_id,
      :gross,
      :opv,
      :vosms,
      :ipn,
      :so,
      :opvr,
      :oosms,
      :net
    ]

  attributes do
    attribute :employee_id, :uuid do
      allow_nil?(false)
      public?(true)
    end

    attribute :gross, :decimal do
      allow_nil?(false)
      public?(true)
    end

    attribute :opv, :decimal do
      allow_nil?(true)
      public?(true)
    end

    attribute :vosms, :decimal do
      allow_nil?(true)
      public?(true)
    end

    attribute :ipn, :decimal do
      allow_nil?(true)
      public?(true)
    end

    attribute :so, :decimal do
      allow_nil?(true)
      public?(true)
    end

    attribute :opvr, :decimal do
      allow_nil?(true)
      public?(true)
    end

    attribute :oosms, :decimal do
      allow_nil?(true)
      public?(true)
    end

    # Сумма к выплате на руки.
    attribute :net, :decimal do
      allow_nil?(true)
      public?(true)
    end
  end

  relationships do
    belongs_to :employee, Pulse.HR.Employee do
      define_attribute?(false)
      public?(true)
    end
  end
end
