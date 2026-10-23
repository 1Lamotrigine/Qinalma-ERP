defmodule Pulse.Ledger do
  @moduledoc """
  Домен регистров накопления: движения ТМЗ, денег и взаиморасчётов.

  Регистры только добавляются. Итоги (`*_totals`) пересобираются
  при закрытии месяца, а не поддерживаются на каждое движение.
  """
  use Ash.Domain, otp_app: :pulse

  resources do
    resource Pulse.Ledger.StockMovement do
      define(:list_stock_movements, action: :read)
    end

    resource Pulse.Ledger.CashMovement do
      define(:list_cash_movements, action: :read)
    end

    resource Pulse.Ledger.SettlementMovement do
      define(:list_settlement_movements, action: :read)
    end

    resource Pulse.Ledger.PayrollMovement do
      define(:list_payroll_movements, action: :read)
    end
  end
end
