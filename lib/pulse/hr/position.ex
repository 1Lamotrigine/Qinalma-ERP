defmodule Pulse.HR.Position do
  @moduledoc """
  Должность организации (раздел 5.5 ТЗ).

  Должность — справочник: она входит в приказ о приёме и хранится,
  чтобы кадровая история не зависела от штатного расписания.
  """
  use Pulse.HR.Resource, table: "hr_positions"

  actions do
    defaults([:read, :destroy])

    create :create do
      accept([:name, :code, :salary])
      validate(present(:name))
    end

    update :update do
      accept([:name, :code, :salary])
    end
  end

  attributes do
    attribute :name, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :code, :string do
      allow_nil?(true)
      public?(true)
    end

    # Оклад по должности — ориентир; в приказе о приёме оклад уточняется.
    attribute :salary, :decimal do
      allow_nil?(true)
      public?(true)
    end
  end

  identities do
    identity(:unique_code, [:code])
  end
end
