defmodule Pulse.Ledger.Checks.SameOrganization do
  @moduledoc """
  Проверка Ash-политик: движение принадлежит активной организации актора.

  Та же причина, что и у справочников: атрибутная мультитенантность
  проверяет организацию только при чтении, а удаление движений идёт
  по идентификатору документа.
  """
  use Ash.Policy.SimpleCheck

  @impl true
  def match?(%{organization_id: actor_organization_id}, %{changeset: %{data: data}}, _opts)
      when not is_nil(actor_organization_id) do
    {:ok, data.organization_id == actor_organization_id}
  end

  def match?(_actor, _context, _opts), do: {:ok, false}

  @impl true
  def describe(_opts), do: "движение принадлежит активной организации пользователя"
end
