defmodule Pulse.Core do
  @moduledoc """
  Домен ядра учёта: организации, подразделения, членства пользователей
  и матрица прав.

  Роли — фиксированный набор (`Pulse.Core.Roles`), матрица «роль × ресурс ×
  действие» хранится в БД (`RolePermission`) и кэшируется
  (`Pulse.Core.Permissions`).
  """
  use Ash.Domain, otp_app: :pulse, extensions: [AshPaperTrail.Domain]

  resources do
    resource Pulse.Core.Organization do
      define(:create_organization, action: :create)
      define(:list_organizations, action: :read)
    end

    resource Pulse.Core.Department do
      define(:list_departments, action: :read)
    end

    resource Pulse.Core.OrganizationMembership do
      define(:list_memberships, action: :read)
    end

    resource Pulse.Core.RolePermission do
      define(:list_role_permissions, action: :read)
    end

    resource Pulse.Core.PeriodLock do
      define(:list_period_locks, action: :read)
    end

    paper_trail do
      include_versions?(true)
    end
  end
end
