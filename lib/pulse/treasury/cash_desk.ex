defmodule Pulse.Treasury.CashDesk do
  @moduledoc """
  Касса организации — место наличных расчётов.

  Касса привязана к ответственному лицу и валюте; на неё ссылаются
  кассовые документы.
  """
  use Pulse.Catalog.Resource, domain: Pulse.Treasury, table: "cash_desks"

  actions do
    create :create do
      accept([:name, :code, :responsible_id, :currency_id, :comment])
      validate(present([:name]))
    end

    update :update do
      accept([:name, :code, :responsible_id, :currency_id, :comment])
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

    # Ответственное лицо — пользователь системы.
    attribute :responsible_id, :uuid do
      allow_nil?(true)
      public?(true)
    end

    attribute :comment, :string do
      allow_nil?(true)
      public?(true)
    end
  end

  relationships do
    belongs_to :currency, Pulse.Catalog.Currency do
      attribute_writable?(true)
      public?(true)
    end
  end

  identities do
    identity(:unique_code, [:code])
  end
end
