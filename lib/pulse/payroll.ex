defmodule Pulse.Payroll do
  @moduledoc """
  Домен заработной платы: начисления, удержания, взносы и выплаты
  (раздел 5.5 ТЗ).

  Расчёт опирается на законодательные параметры (`statutory_rates`) и
  на карточки сотрудников (`Pulse.HR`). Все ресурсы мультитенантны и
  аудируются AshPaperTrail.
  """
  use Ash.Domain, otp_app: :pulse, extensions: [AshPaperTrail.Domain]

  resources do
    resource Pulse.Payroll.Accrual do
      define(:list_accruals, action: :read)
    end

    resource Pulse.Payroll.AccrualLine do
      define(:list_accrual_lines, action: :read)
    end

    resource Pulse.Payroll.PaymentStatement do
      define(:list_payment_statements, action: :read)
    end

    paper_trail do
      include_versions?(true)
    end
  end
end
