defmodule Pulse.Core.Checks.MyOrganizations do
  @moduledoc """
  Политика Ash (фильтр): пользователь видит только организации, в которых
  состоит (`OrganizationMembership`).

  Для актора без пользователя — пустой список.
  """
  use Ash.Policy.FilterCheck
  require Ash.Query

  @impl true
  def filter(%{id: user_id}, _context, _opts) when not is_nil(user_id) do
    [id: {:in, member_organization_ids(user_id)}]
  end

  def filter(_actor, _context, _opts), do: [id: {:in, []}]

  @impl true
  def describe(_opts), do: "пользователь состоит в организации"

  defp member_organization_ids(user_id) do
    query = Ash.Query.filter(Pulse.Core.OrganizationMembership, user_id == ^user_id)

    case Ash.read(query, domain: Pulse.Core, authorize?: false) do
      {:ok, memberships} -> Enum.map(memberships, & &1.organization_id)
      _ -> []
    end
  end
end
