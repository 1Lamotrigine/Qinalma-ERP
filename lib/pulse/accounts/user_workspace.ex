defmodule Pulse.Accounts.UserWorkspace do
  @moduledoc """
  Состояние рабочей области пользователя: открытые вкладки, избранное
  и активная организация.

  Список вкладок хранится как JSONB-массив, активная вкладка — отдельным полем.
  Восстанавливается после входа.
  """
  use Ash.Resource,
    otp_app: :pulse,
    domain: Pulse.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table("user_workspaces")
    repo(Pulse.Repo)
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      accept([:tabs, :active_tab, :favorites, :active_organization_id])
      change(set_attribute(:user_id, actor(:id)))
    end

    update :update do
      accept([:tabs, :active_tab, :favorites, :active_organization_id])
    end
  end

  policies do
    policy action_type([:read, :update, :destroy]) do
      authorize_if(expr(user_id == ^actor(:id)))
    end

    policy action_type(:create) do
      authorize_if(actor_present())
    end
  end

  attributes do
    uuid_primary_key(:id)

    attribute :user_id, :uuid do
      allow_nil?(false)
      public?(true)
    end

    attribute :tabs, {:array, :map} do
      allow_nil?(false)
      default([])
      public?(true)
    end

    attribute :active_tab, :string do
      allow_nil?(true)
      public?(true)
    end

    attribute :favorites, {:array, :string} do
      allow_nil?(false)
      default([])
      public?(true)
    end

    # Активная организация: выбирается в шапке, хранится между сессиями.
    attribute :active_organization_id, :uuid do
      allow_nil?(true)
      public?(true)
    end

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  identities do
    identity(:unique_user, [:user_id])
  end
end
