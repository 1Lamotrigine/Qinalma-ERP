defmodule Pulse.Catalog.IsolationTest do
  @moduledoc """
  Изоляция данных по организациям (мультитенантность по `organization_id`).

  Критерий этапа 2: данные чужой организации недоступны — ни в списке,
  ни по прямой ссылке.
  """
  use Pulse.DataCase, async: true

  import Pulse.Factory
  require Ash.Query

  alias Pulse.Catalog
  alias Pulse.Core

  setup do
    seed_default_permissions!()

    alfa = create_organization(%{name: "Альфа"})
    beta = create_organization(%{name: "Бета"})

    user = create_user()
    create_membership(user, alfa, "admin")
    create_membership(user, beta, "admin")

    actor_alfa = Core.Actor.build(user, [%{organization_id: alfa.id, role: "admin"}], alfa.id)
    actor_beta = Core.Actor.build(user, [%{organization_id: beta.id, role: "admin"}], beta.id)

    %{alfa: alfa, beta: beta, user: user, actor_alfa: actor_alfa, actor_beta: actor_beta}
  end

  describe "списки справочников" do
    test "контрагент виден только в своей организации", %{
      actor_alfa: actor_alfa,
      actor_beta: actor_beta
    } do
      counterparty = create_counterparty(actor_alfa, %{name: "Альфа-Поставщик"})

      assert [%{id: id}] = list(Catalog.Counterparty, actor_alfa)
      assert id == counterparty.id

      assert list(Catalog.Counterparty, actor_beta) == []
    end

    test "номенклатура видна только в своей организации", %{
      actor_alfa: actor_alfa,
      actor_beta: actor_beta
    } do
      create_nomenclature(actor_alfa, %{name: "Товар Альфы"})

      assert [_one] = list(Catalog.Nomenclature, actor_alfa)
      assert list(Catalog.Nomenclature, actor_beta) == []
    end
  end

  describe "доступ по идентификатору" do
    test "запись чужой организации не читается", %{
      actor_alfa: actor_alfa,
      actor_beta: actor_beta
    } do
      counterparty = create_counterparty(actor_alfa)

      query =
        Catalog.Counterparty
        |> Ash.Query.filter(id == ^counterparty.id)

      assert {:ok, [%{id: found_id}]} =
               Ash.read(query, actor: actor_alfa, tenant: actor_alfa.organization_id)

      assert found_id == counterparty.id

      assert {:ok, []} =
               Ash.read(query, actor: actor_beta, tenant: actor_beta.organization_id)
    end

    test "чужая запись не обновляется", %{actor_alfa: actor_alfa, actor_beta: actor_beta} do
      counterparty = create_counterparty(actor_alfa, %{name: "Не трогать"})

      result =
        counterparty
        |> Ash.Changeset.for_update(:update, %{name: "Взломано"})
        |> Ash.Changeset.set_tenant(actor_beta.organization_id)
        |> Ash.update(actor: actor_beta)

      assert forbidden?(result)
      assert [%{name: "Не трогать"}] = list(Catalog.Counterparty, actor_alfa)
    end

    test "чужая запись не удаляется", %{actor_alfa: actor_alfa, actor_beta: actor_beta} do
      counterparty = create_counterparty(actor_alfa)

      result =
        counterparty
        |> Ash.Changeset.for_destroy(:destroy)
        |> Ash.Changeset.set_tenant(actor_beta.organization_id)
        |> Ash.destroy(actor: actor_beta)

      assert {:error, _error} = result

      assert [%{id: id}] = list(Catalog.Counterparty, actor_alfa)
      assert id == counterparty.id
    end
  end

  describe "чтение без организации" do
    test "мультитенантный справочник без тенанта недоступен", %{actor_alfa: actor_alfa} do
      result =
        Catalog.Counterparty
        |> Ash.read(actor: actor_alfa)

      assert {:error, %Ash.Error.Invalid{errors: [%Ash.Error.Invalid.TenantRequired{}]}} = result
    end
  end

  defp list(resource, actor) do
    assert {:ok, records} = Ash.read(resource, actor: actor, tenant: actor.organization_id)
    records
  end

  # Чужая запись недоступна: политика запретила, запись не найдена в
  # организации актора (`StaleRecord`) или удаление отклонено ссылками.
  defp forbidden?({:error, %Ash.Error.Forbidden{}}), do: true

  defp forbidden?({:error, error}) do
    messages = inspect(error)

    String.contains?(messages, "Forbidden") or
      String.contains?(messages, "StaleRecord") or
      String.contains?(messages, "not be found") or
      String.contains?(messages, "would leave records behind")
  end

  defp forbidden?(_other), do: false
end
