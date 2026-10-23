defmodule Pulse.Core.Department do
  @moduledoc """
  Подразделение организации.

  Мультитенантно: данные фильтруются по `organization_id`
  (атрибутная мультитенантность, раздел 7 ТЗ).
  """
  use Ash.Resource,
    otp_app: :pulse,
    domain: Pulse.Core,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table("departments")
    repo(Pulse.Repo)
  end

  multitenancy do
    strategy(:attribute)
    attribute(:organization_id)
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      accept([:name, :code])
      validate(present(:name))
    end

    update :update do
      accept([:name, :code])
    end
  end

  policies do
    policy action_type([:read, :create, :update, :destroy]) do
      authorize_if(Pulse.Core.Checks.RoleAllowed)
    end
  end

  attributes do
    uuid_primary_key(:id)

    attribute :organization_id, :uuid do
      allow_nil?(false)
      public?(true)
    end

    attribute :name, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :code, :string do
      allow_nil?(true)
      public?(true)
    end

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  relationships do
    belongs_to :organization, Pulse.Core.Organization do
      attribute_writable?(false)
      public?(true)
    end
  end

  identities do
    identity(:unique_code, [:code])
  end
end
