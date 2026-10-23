defmodule Pulse.Core.Actor do
  @moduledoc """
  Актор запроса: пользователь с активной организацией и ролью в ней.

  Роль в организации определяется членством (`OrganizationMembership`)
  и вместе с матрицей прав (`Pulse.Core.Permissions`) решает, что можно
  делать (`Pulse.Core.Checks.RoleAllowed`).
  """

  defstruct [:id, :email, :organization_id, :role]

  @type t :: %__MODULE__{
          id: String.t(),
          email: String.t(),
          organization_id: String.t() | nil,
          role: String.t() | nil
        }

  @doc """
  Строит актор из пользователя, активной организации и матрицы членств.

  Активная организация берётся, только если пользователь состоит в ней;
  иначе — первая организация из членств. Так чужая или удалённая
  организация из сохранённого состояния не попадает в запросы.
  """
  def build(user, memberships, organization_id \\ nil) do
    organization_id =
      if Enum.any?(memberships, &(&1.organization_id == organization_id)) do
        organization_id
      else
        Enum.find_value(memberships, & &1.organization_id)
      end

    role =
      Enum.find_value(memberships, fn membership ->
        if membership.organization_id == organization_id, do: membership.role
      end)

    %__MODULE__{
      id: user.id,
      email: to_string(user.email),
      organization_id: organization_id,
      role: role
    }
  end
end
