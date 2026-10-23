defmodule Pulse.Accounts do
  @moduledoc """
  Домен учётных записей: пользователи, аутентификация и права доступа.

  На этапе 0 содержит только ресурс пользователя. Организации, роли и
  матрица прав появляются на этапе 2.
  """
  use Ash.Domain, otp_app: :pulse, extensions: [AshAuthentication]
  require Ash.Query

  resources do
    resource Pulse.Accounts.User do
      define(:get_user_by_email, action: :get_by_email, args: [:email])
      define(:get_user_by_id, action: :get_by_id, args: [:id], get?: true)
    end

    resource(Pulse.Accounts.Token)

    resource(Pulse.Accounts.UserWorkspace) do
      define(:get_workspace_for_user, action: :read, get_by: [:user_id])
    end
  end

  @doc """
  Возвращает рабочую область пользователя, создавая её при первом обращении.

  Активная организация проверяется на членство: если сохранённая
  организация больше не доступна (членство отозвано, организация
  удалена), берётся первая доступная.
  """
  def load_or_create_workspace(user) do
    case get_workspace_for_user(user.id, actor: user) do
      {:ok, %Pulse.Accounts.UserWorkspace{} = workspace} ->
        normalize_active_organization(workspace, user)

      _ ->
        Pulse.Accounts.UserWorkspace
        |> Ash.Changeset.for_create(:create, %{}, actor: user)
        |> Ash.create!(actor: user)
    end
  end

  defp normalize_active_organization(workspace, user) do
    memberships = memberships_of(user)

    organization_id =
      if Enum.any?(memberships, &(&1.organization_id == workspace.active_organization_id)) do
        workspace.active_organization_id
      else
        Enum.find_value(memberships, & &1.organization_id)
      end

    if organization_id == workspace.active_organization_id do
      workspace
    else
      case save_workspace(workspace, user, %{active_organization_id: organization_id}) do
        {:ok, workspace} -> workspace
        _ -> workspace
      end
    end
  end

  defp memberships_of(user) do
    query = Ash.Query.filter(Pulse.Core.OrganizationMembership, user_id == ^user.id)

    case Ash.read(query, actor: user, authorize?: false) do
      {:ok, memberships} -> memberships
      _ -> []
    end
  end

  @doc """
  Сохраняет состояние рабочей области: вкладки, активную вкладку, избранное.
  """
  def save_workspace(workspace, user, attrs) do
    workspace
    |> Ash.Changeset.for_update(:update, attrs)
    |> Ash.update(actor: user)
  end
end
