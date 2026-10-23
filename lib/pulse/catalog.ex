defmodule Pulse.Catalog do
  @moduledoc """
  Домен справочников: контрагенты, договоры, номенклатура, склады,
  единицы измерения, валюты и банки.

  Все ресурсы домена мультитенантны по `organization_id` и аудируются
  AshPaperTrail.
  """
  use Ash.Domain, otp_app: :pulse, extensions: [AshPaperTrail.Domain]

  resources do
    resource Pulse.Catalog.Counterparty do
      define(:list_counterparties, action: :read)
    end

    resource Pulse.Catalog.Contract do
      define(:list_contracts, action: :read)
    end

    resource Pulse.Catalog.Nomenclature do
      define(:list_nomenclature, action: :read)
    end

    resource Pulse.Catalog.Warehouse do
      define(:list_warehouses, action: :read)
    end

    resource Pulse.Catalog.Unit do
      define(:list_units, action: :read)
    end

    resource Pulse.Catalog.Currency do
      define(:list_currencies, action: :read)
    end

    resource Pulse.Catalog.Bank do
      define(:list_banks, action: :read)
    end

    paper_trail do
      include_versions?(true)
    end
  end
end
