defmodule Pulse.Core.PeriodLock do
  @moduledoc """
  Состояние учётных периодов организации.

  Одна строка на организацию: список закрытых месяцев и дата запрета
  правок. Так состояние всегда согласовано — нельзя закрыть месяц,
  забыв обновить дату запрета, и наоборот.

  Закрытый месяц хранится первым числом (`2026-10-01`); проведение
  документов внутри него запрещено (`Pulse.Accounting.Periods`).
  """
  use Ash.Resource,
    otp_app: :pulse,
    domain: Pulse.Core,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table("period_locks")
    repo(Pulse.Repo)
  end

  multitenancy do
    strategy(:attribute)
    attribute(:organization_id)
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      accept([:organization_id, :closed_periods, :prohibition_date, :closed_at, :closed_by])
      validate(present([:organization_id]))
    end

    update :update do
      accept([:closed_periods, :prohibition_date, :closed_at, :closed_by])
    end
  end

  policies do
    # Читают состояние периода все роли: оно нужно шапке и документам.
    policy action_type(:read) do
      authorize_if(Pulse.Core.Checks.RoleAllowed)
    end

    # Менять периоды может только главный бухгалтер и администратор —
    # это защита от закрытия месяца рядовым бухгалтером.
    policy action_type([:create, :update, :destroy]) do
      authorize_if(expr(^actor(:role) in ["chief_accountant", "admin"]))
    end
  end

  attributes do
    uuid_primary_key(:id)

    attribute :organization_id, :uuid do
      allow_nil?(false)
      public?(true)
    end

    # Закрытые месяцы: первый день каждого месяца.
    attribute :closed_periods, {:array, :date} do
      allow_nil?(false)
      default([])
      public?(true)
    end

    # Дата запрета правок: документы раньше неё менять нельзя.
    attribute :prohibition_date, :date do
      allow_nil?(true)
      public?(true)
    end

    attribute :closed_at, :utc_datetime_usec do
      allow_nil?(true)
      public?(true)
    end

    attribute :closed_by, :uuid do
      allow_nil?(true)
      public?(true)
    end

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  identities do
    identity(:unique_organization, [:organization_id])
  end
end
