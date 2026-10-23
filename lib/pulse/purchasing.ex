defmodule Pulse.Purchasing do
  @moduledoc """
  Домен закупок: поступления ТМЗ и услуг.
  """
  use Ash.Domain, otp_app: :pulse, extensions: [AshPaperTrail.Domain]

  resources do
    resource Pulse.Purchasing.Receipt do
      define(:list_receipts, action: :read)
    end

    resource Pulse.Purchasing.ReceiptLine do
      define(:list_receipt_lines, action: :read)
    end

    paper_trail do
      include_versions?(true)
    end
  end
end
