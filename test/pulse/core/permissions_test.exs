defmodule Pulse.Core.PermissionsTest do
  @moduledoc """
  Матрица прав «роль × ресурс × действие».

  Критерий этапа 2: доступ проверяется по матрице из БД, запрет по
  умолчанию, а роль без гранта не видит справочник (кладовщик — банки).
  """
  use Pulse.DataCase, async: true

  import Pulse.Factory
  require Ash.Query

  alias Pulse.Catalog
  alias Pulse.Core
  alias Pulse.Core.Checks.RoleAllowed

  setup do
    seed_default_permissions!()
    :ok
  end

  describe "матрица по умолчанию" do
    test "в БД столько же строк, сколько в матрице по умолчанию" do
      {:ok, rows} = Ash.read(Core.RolePermission, authorize?: false)

      assert length(rows) == length(Core.Roles.default_matrix())
    end

    test "администратору разрешено всё" do
      for resource <- Core.Roles.resources(), action <- Core.Roles.actions() do
        assert Core.Permissions.allowed?("admin", resource, action)
      end
    end

    test "неизвестная комбинация запрещена (запрет по умолчанию)" do
      refute Core.Permissions.allowed?("storekeeper", "catalog.bank", "read")
      refute Core.Permissions.allowed?(nil, "catalog.counterparty", "read")
      refute Core.Permissions.allowed?("storekeeper", "catalog.unknown", "read")
    end

    test "грант без действия раскрывается во все действия" do
      for action <- Core.Roles.actions() do
        assert Core.Permissions.allowed?("admin", "catalog.bank", action)
      end
    end

    test "кладовщик может читать номенклатуру, но не менять её" do
      assert Core.Permissions.allowed?("storekeeper", "catalog.nomenclature", "read")
      refute Core.Permissions.allowed?("storekeeper", "catalog.nomenclature", "destroy")
    end
  end

  describe "проверка политики Ash" do
    test "кладовщик не видит банки" do
      actor = create_actor("storekeeper")
      create_bank(actor)

      assert {:error, %Ash.Error.Forbidden{}} =
               Ash.read(Catalog.Bank, actor: actor, tenant: actor.organization_id)
    end

    test "кладовщик видит номенклатуру" do
      actor = create_actor("storekeeper")

      create_nomenclature(create_actor("accountant", actor.organization_id), %{
        name: "Товар кладовщика"
      })

      assert {:ok, [%{name: "Товар кладовщика"}]} =
               Ash.read(Catalog.Nomenclature, actor: actor, tenant: actor.organization_id)
    end

    test "кладовщик не может создать банк" do
      actor = create_actor("storekeeper")

      result =
        Ash.Changeset.for_create(Catalog.Bank, :create, %{bic: "000345000099", name: "Тест-Банк"})
        |> Ash.Changeset.set_tenant(actor.organization_id)
        |> Ash.create(actor: actor)

      assert {:error, %Ash.Error.Forbidden{}} = result
    end

    test "бухгалтер видит банки" do
      actor = create_actor("accountant")
      create_bank(actor)

      assert {:ok, [_bank]} =
               Ash.read(Catalog.Bank, actor: actor, tenant: actor.organization_id)
    end
  end

  describe "изменение матрицы" do
    test "выдача гранта открывает доступ без перезапуска" do
      actor = create_actor("storekeeper")
      create_bank(actor)

      assert {:error, %Ash.Error.Forbidden{}} =
               Ash.read(Catalog.Bank, actor: actor, tenant: actor.organization_id)

      grant!("storekeeper", "catalog.bank", "read")

      assert {:ok, [_bank]} =
               Ash.read(Catalog.Bank, actor: actor, tenant: actor.organization_id)
    end

    test "отзыв гранта закрывает доступ" do
      actor = create_actor("accountant")
      create_bank(actor)

      assert {:ok, [_bank]} =
               Ash.read(Catalog.Bank, actor: actor, tenant: actor.organization_id)

      revoke!("accountant", "catalog.bank", "read")

      assert {:error, %Ash.Error.Forbidden{}} =
               Ash.read(Catalog.Bank, actor: actor, tenant: actor.organization_id)
    end

    test "ключ ресурса выводится из модуля" do
      assert RoleAllowed.resource_key(Catalog.Counterparty) == "catalog.counterparty"
      assert RoleAllowed.resource_key(Catalog.Nomenclature) == "catalog.nomenclature"
      assert RoleAllowed.resource_key(Core.Organization) == "core.organization"

      # Переопределения для ресурсов, чей ключ в матрице короче.
      assert RoleAllowed.resource_key(Core.OrganizationMembership) == "core.membership"
      assert RoleAllowed.resource_key(Core.RolePermission) == "core.role_permission"
    end
  end

  defp grant!(role, resource, action) do
    Ash.Changeset.for_create(Core.RolePermission, :create, %{
      role: role,
      resource: resource,
      action: action,
      allowed?: true
    })
    |> Ash.create!(authorize?: false)

    Core.Permissions.reload()
  end

  defp revoke!(role, resource, action) do
    query =
      Core.RolePermission
      |> Ash.Query.filter(role == ^role and resource == ^resource and action == ^action)

    {:ok, [row]} = Ash.read(query, authorize?: false)

    row
    |> Ash.Changeset.for_update(:update, %{allowed?: false})
    |> Ash.update!(authorize?: false)

    Core.Permissions.reload()
  end

  defp create_bank(actor) do
    Ash.Changeset.for_create(Catalog.Bank, :create, %{
      bic:
        "0003450000#{System.unique_integer([:positive]) |> rem(100) |> Integer.to_string() |> String.pad_leading(2, "0")}",
      name: "Банк-#{System.unique_integer([:positive])}"
    })
    |> Ash.Changeset.set_tenant(actor.organization_id)
    |> Ash.create!(authorize?: false)
  end
end
