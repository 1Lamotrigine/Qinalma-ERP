defmodule Pulse.Core.RolePermission do
  @moduledoc """
  Строка матрицы прав «роль × ресурс × действие».

  Глобальный ресурс: одна матрица на инсталляцию. Доступ разрешён по
  умолчанию запрещён — отсутствие строки означает запрет. Кэш
  `Pulse.Core.Permissions` перезагружается после каждого изменения.
  """
  use Ash.Resource,
    otp_app: :pulse,
    domain: Pulse.Core,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table("role_permissions")
    repo(Pulse.Repo)
  end

  actions do
    defaults([:read])

    create :create do
      accept([:role, :resource, :action, :allowed?])
      change(Pulse.Core.Changes.ReloadPermissionCache)
      validate(present([:role, :resource, :action]))
      validate(one_of(:role, Pulse.Core.Roles.keys()))
      validate(one_of(:action, Pulse.Core.Roles.actions()))
    end

    update :update do
      accept([:allowed?])
      require_atomic?(false)
      change(Pulse.Core.Changes.ReloadPermissionCache)
    end

    destroy :destroy do
      require_atomic?(false)
      change(Pulse.Core.Changes.ReloadPermissionCache)
    end
  end

  policies do
    # Матрицу читают все разрешённые роли (для экрана), меняет — только админ.
    policy action_type(:read) do
      authorize_if(Pulse.Core.Checks.RoleAllowed)
    end

    policy action_type([:create, :update, :destroy]) do
      authorize_if(Pulse.Core.Checks.RoleAllowed)
    end
  end

  attributes do
    uuid_primary_key(:id)

    attribute :role, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :resource, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :action, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :allowed?, :boolean do
      allow_nil?(false)
      default(true)
      public?(true)
    end

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  identities do
    identity(:unique_rule, [:role, :resource, :action])
  end
end
