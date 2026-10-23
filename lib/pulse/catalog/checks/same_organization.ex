defmodule Pulse.Catalog.Checks.SameOrganization do
  @moduledoc """
  Проверка Ash-политик: запись принадлежит активной организации актора.

  Нужна для изменения и удаления. Атрибутная мультитенантность проверяет
  организацию только при чтении: запись, загруженную в одной организации,
  иначе можно было бы изменить или удалить после переключения на другую.
  """
  use Ash.Policy.SimpleCheck

  @impl true
  def match?(%{organization_id: actor_organization_id}, %{changeset: %{data: data}}, _opts)
      when not is_nil(actor_organization_id) do
    {:ok, data.organization_id == actor_organization_id}
  end

  def match?(_actor, _context, _opts), do: {:ok, false}

  @impl true
  def describe(_opts), do: "запись принадлежит активной организации пользователя"
end
