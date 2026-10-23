defmodule Pulse.Purchasing.ReceiptLine do
  @moduledoc """
  Строка поступления: номенклатура, количество, цена и сумма.
  """
  use Pulse.Accounting.DocumentLine,
    domain: Pulse.Purchasing,
    table: "purchasing_receipt_lines"

  attributes do
    attribute :nomenclature_id, :uuid do
      allow_nil?(false)
      public?(true)
    end
  end

  relationships do
    belongs_to :document, Pulse.Purchasing.Receipt do
      define_attribute?(false)
      public?(true)
    end

    belongs_to :nomenclature, Pulse.Catalog.Nomenclature do
      define_attribute?(false)
      public?(true)
    end
  end
end
