defmodule Pulse.Core.OrganizationMembership do
  @moduledoc """
  Членство пользователя в организации: `пользователь × организация × роль`.

  Глобальный ресурс (не мультитенантный): нужен, чтобы построить актор
  и список организаций пользователя до выбора активной организации.
  """
  use Ash.Resource,
    otp_app: :pulse,
    domain: Pulse.Core,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table("organization_memberships")
    repo(Pulse.Repo)
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      accept([:user_id, :organization_id, :role])
      validate(one_of(:role, Pulse.Core.Roles.keys()))
      validate(present([:user_id, :organization_id, :role]))
    end

    update :update do
      accept([:role])
      validate(one_of(:role, Pulse.Core.Roles.keys()))
    end
  end

  policies do
    # Членства видит сам пользователь и администратор; изменения — только админ.
    policy action_type(:read) do
      authorize_if(expr(user_id == ^actor(:id)))
      authorize_if(Pulse.Core.Checks.RoleAllowed)
    end

    policy action_type([:create, :update, :destroy]) do
      authorize_if(Pulse.Core.Checks.RoleAllowed)
    end
  end

  attributes do
    uuid_primary_key(:id)

    attribute :user_id, :uuid do
      allow_nil?(false)
      public?(true)
    end

    attribute :organization_id, :uuid do
      allow_nil?(false)
      public?(true)
    end

    attribute :role, :string do
      allow_nil?(false)
      public?(true)
    end

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  identities do
    identity(:unique_membership, [:user_id, :organization_id])
  end
end
