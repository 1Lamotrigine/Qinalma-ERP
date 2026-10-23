defmodule Pulse.Catalog.AuditTest do
  @moduledoc """
  Аудит изменений справочников (AshPaperTrail).

  Критерий этапа 2: аудит фиксирует создание, изменение и удаление
  записей, включая организацию-владельца.
  """
  use Pulse.DataCase, async: true

  import Pulse.Factory
  require Ash.Query

  alias Pulse.Catalog
  alias Pulse.Core

  setup do
    seed_default_permissions!()

    organization = create_organization(%{name: "Аудит"})
    user = create_user()
    create_membership(user, organization, "admin")

    actor =
      Core.Actor.build(
        user,
        [%{organization_id: organization.id, role: "admin"}],
        organization.id
      )

    %{actor: actor, organization: organization}
  end

  test "создание записывается в версии", %{actor: actor} do
    counterparty = create_counterparty(actor, %{name: "Аудит-Контрагент"})

    assert [version] = versions(counterparty.id, actor)

    assert version.version_action_type == :create
    assert version.version_action_name == :create
    assert version.changes["name"] == "Аудит-Контрагент"
    assert version.organization_id == actor.organization_id
    assert version.version_source_id == counterparty.id
  end

  test "изменение записывается в версии", %{actor: actor} do
    counterparty = create_counterparty(actor, %{name: "До"})

    counterparty
    |> Ash.Changeset.for_update(:update, %{name: "После"})
    |> Ash.Changeset.set_tenant(actor.organization_id)
    |> Ash.update!(actor: actor)

    versions = versions(counterparty.id, actor)

    assert Enum.map(versions, & &1.version_action_type) == [:update, :create]
    assert hd(versions).changes["name"] == "После"
    assert hd(versions).changes["name_from"] == nil
  end

  test "удаление записывается в версии", %{actor: actor} do
    counterparty = create_counterparty(actor, %{name: "Удаляемый"})

    counterparty
    |> Ash.Changeset.for_destroy(:destroy)
    |> Ash.Changeset.set_tenant(actor.organization_id)
    |> Ash.destroy!(actor: actor)

    versions = versions(counterparty.id, actor)

    assert Enum.map(versions, & &1.version_action_type) == [:destroy, :create]

    # Удаление фиксируется без данных: изменения пусты, но факт есть.
    assert hd(versions).changes == %{}
  end

  test "версии изолированы по организациям", %{actor: actor} do
    other = create_actor("admin")
    counterparty = create_counterparty(other, %{name: "Чужой контрагент"})

    assert versions(counterparty.id, actor) == []
  end

  defp versions(counterparty_id, actor) do
    query =
      Catalog.Counterparty.Version
      |> Ash.Query.filter(version_source_id == ^counterparty_id)
      |> Ash.Query.sort(version_inserted_at: :desc)

    assert {:ok, versions} = Ash.read(query, actor: actor, tenant: actor.organization_id)
    versions
  end
end
