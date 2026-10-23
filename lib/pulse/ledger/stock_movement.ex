defmodule Pulse.Ledger.StockMovement do
  @moduledoc """
  Движение ТМЗ по складу: приход или расход.

  Количество и стоимость хранятся со знаком операции:
  `:receipt` — приход, `:expense` — расход. Себестоимость расхода
  считается при проведении по средней взвешенной.
  """
  use Pulse.Ledger.Resource, table: "stock_movements"

  postgres do
    # Остатки читаются по складу и номенклатуре за период.
    custom_indexes do
      index([:organization_id, :warehouse_id, :nomenclature_id, :period],
        name: "stock_movements_balance_index"
      )

      index([:document_type, :document_id], name: "stock_movements_document_index")
    end
  end

  attributes do
    attribute :record_type, :atom do
      allow_nil?(false)
      constraints(one_of: [:receipt, :expense])
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

    attribute :quantity, :decimal do
      allow_nil?(false)
      public?(true)
    end

    attribute :cost, :decimal do
      allow_nil?(false)
      public?(true)
    end

    attribute :warehouse_id, :uuid do
      allow_nil?(false)
      public?(true)
    end

    attribute :nomenclature_id, :uuid do
      allow_nil?(false)
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
        :record_type,
        :period,
        :doc_date,
        :quantity,
        :cost,
        :warehouse_id,
        :nomenclature_id
      ])
    end

    # Переоценка движения при пересчёте себестоимости за месяц.
    # Меняется только стоимость: количество и склад зафиксированы.
    update :revalue do
      accept([:cost])
      require_atomic?(false)
    end
  end
end
