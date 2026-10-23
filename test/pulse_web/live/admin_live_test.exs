defmodule PulseWeb.AdminLiveTest do
  @moduledoc """
  Экран «Настройки пользователей и прав»: пользователи, роли и матрица прав.
  """
  use PulseWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Pulse.Factory
  require Ash.Query

  alias Pulse.Core

  setup do
    seed_default_permissions!()

    organization = create_organization(%{name: "Админ-Орг"})
    user = create_user()
    create_membership(user, organization, "admin")

    %{conn: log_in_user(build_conn(), user), user: user, organization: organization}
  end

  test "экран открывается из журнала администрирования", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    view |> element("#ws-nav button", "Администрирование") |> render_click()

    view
    |> element("button[phx-click='open-item'][phx-value-title='Настройки пользователей и прав']")
    |> render_click()

    assert has_element?(view, "#admin-matrix")
  end

  test "список пользователей показывает роли", %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, "/?tab=adm|Настройки пользователей и прав")

    view |> element("button[phx-value-view='users']") |> render_click()

    assert has_element?(view, "#admin-users")

    html = render(view)

    assert html =~ to_string(user.email)
    assert html =~ "Админ-Орг"
    assert html =~ "Администратор"
  end

  test "матрица показывает ресурсы и действия", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/?tab=adm|Настройки пользователей и прав")

    assert has_element?(view, "#admin-matrix")

    for resource <- Core.Roles.resources() do
      assert has_element?(view, "tr td", resource_label(resource))
    end
  end

  test "переключение роли меняет набор грантов", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/?tab=adm|Настройки пользователей и прав")

    # У администратора отмечено чтение банков.
    assert has_element?(view, "#perm-admin-catalog\\.bank-read[checked]")

    view
    |> element("#admin-role")
    |> render_change(%{"role" => "storekeeper"})

    # У кладовщика банки закрыты.
    refute has_element?(view, "#perm-storekeeper-catalog\\.bank-read[checked]")
  end

  test "снятие галота закрывает доступ роли", %{conn: conn, organization: organization} do
    {:ok, view, _html} = live(conn, "/?tab=adm|Настройки пользователей и прав")

    view
    |> element("#admin-role")
    |> render_change(%{"role" => "accountant"})

    assert has_element?(view, "#perm-accountant-catalog\\.bank-read[checked]")

    view
    |> element("#perm-accountant-catalog\\.bank-read")
    |> render_click()

    refute has_element?(view, "#perm-accountant-catalog\\.bank-read[checked]")

    storekeeper = create_actor("accountant", organization.id)

    assert {:error, %Ash.Error.Forbidden{}} =
             Ash.read(Pulse.Catalog.Bank, actor: storekeeper, tenant: organization.id)
  end

  test "смена роли участника сохраняется", %{conn: conn, organization: organization} do
    member = create_user()
    membership = create_membership(member, organization, "accountant")

    {:ok, view, _html} = live(conn, "/?tab=adm|Настройки пользователей и прав")
    view |> element("button[phx-value-view='users']") |> render_click()

    view
    |> element("select[phx-value-id='#{membership.id}']")
    |> render_change(%{"role" => "storekeeper", "id" => membership.id})

    {:ok, [updated]} =
      Core.OrganizationMembership
      |> Ash.Query.filter(id == ^membership.id)
      |> Ash.read(authorize?: false)

    assert updated.role == "storekeeper"
  end

  defp resource_label(resource) do
    resource
    |> String.split(".")
    |> List.last()
    |> String.replace("_", " ")
    |> String.capitalize()
  end
end
