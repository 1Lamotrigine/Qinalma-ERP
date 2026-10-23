defmodule PulseWeb.CatalogLiveTest do
  @moduledoc """
  Работа со справочниками в рабочей области: журнал с реальными данными,
  форма элемента, переключение активной организации.
  """
  use PulseWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Pulse.Factory

  alias Pulse.Catalog
  alias Pulse.Core

  setup do
    seed_default_permissions!()

    alfa = create_organization(%{name: "Альфа-Орг"})
    beta = create_organization(%{name: "Бета-Орг"})

    user = create_user()
    create_membership(user, alfa, "admin")
    create_membership(user, beta, "admin")

    actor_alfa = Core.Actor.build(user, [%{organization_id: alfa.id, role: "admin"}], alfa.id)
    actor_beta = Core.Actor.build(user, [%{organization_id: beta.id, role: "admin"}], beta.id)

    create_counterparty(actor_alfa, %{name: "Альфа-Контрагент"})
    create_counterparty(actor_beta, %{name: "Бета-Контрагент"})

    %{
      conn: log_in_user(build_conn(), user),
      user: user,
      alfa: alfa,
      beta: beta,
      actor_alfa: actor_alfa,
      actor_beta: actor_beta
    }
  end

  describe "журнал справочника" do
    test "показывает данные активной организации", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?tab=#{URI.encode_www_form("buy|Контрагенты")}")

      html = render(view)

      assert html =~ "Альфа-Контрагент"
      refute html =~ "Бета-Контрагент"
    end

    test "показывает колонки справочника", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?tab=#{URI.encode_www_form("buy|Контрагенты")}")

      html = render(view)

      assert html =~ "Тип"
      assert html =~ "Юридическое лицо"
    end
  end

  describe "форма элемента справочника" do
    test "создание элемента", %{conn: conn, actor_alfa: actor_alfa} do
      {:ok, view, _html} = live(conn, "/?tab=#{URI.encode_www_form("buy|Контрагенты")}")

      view
      |> element("button[phx-click='create-document']")
      |> render_click()

      assert has_element?(view, "#catalog-form")

      view
      |> form("#catalog-form", catalog: %{name: "Новый контрагент", kind: "legal"})
      |> render_submit()

      assert render(view) =~ "Новый контрагент"

      assert [_one, _two] = list(Catalog.Counterparty, actor_alfa)
    end

    test "валидация показывает ошибку", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?tab=#{URI.encode_www_form("buy|Контрагенты")}")

      view |> element("button[phx-click='create-document']") |> render_click()

      html =
        view
        |> form("#catalog-form", catalog: %{name: "", kind: "legal"})
        |> render_submit()

      assert html =~ "Проверьте поля формы"
    end

    test "редактирование элемента", %{conn: conn, actor_alfa: actor_alfa} do
      [counterparty] = list(Catalog.Counterparty, actor_alfa)

      {:ok, view, _html} = live(conn, "/?tab=#{URI.encode_www_form("buy|Контрагенты")}")

      view
      |> element("tr[phx-value-id='#{counterparty.id}']")
      |> render_click()

      assert has_element?(view, "#catalog-form")

      view
      |> form("#catalog-form", catalog: %{name: "Переименованный"})
      |> render_submit()

      assert render(view) =~ "Переименованный"
      assert [%{name: "Переименованный"}] = list(Catalog.Counterparty, actor_alfa)
    end

    test "отмена закрывает форму", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?tab=#{URI.encode_www_form("buy|Контрагенты")}")

      view |> element("button[phx-click='create-document']") |> render_click()
      assert has_element?(view, "#catalog-form")

      view |> element("button[phx-click='catalog-cancel']") |> render_click()

      refute has_element?(view, "#catalog-form")
    end
  end

  describe "переключение активной организации" do
    test "журнал показывает данные выбранной организации", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?tab=#{URI.encode_www_form("buy|Контрагенты")}")

      assert render(view) =~ "Альфа-Контрагент"

      html = render_change(view, "switch-organization", %{"value" => org_id(view, "Бета-Орг")})

      assert html =~ "Бета-Контрагент"
      refute html =~ "Альфа-Контрагент"
    end

    test "выбор сохраняется в рабочей области", %{conn: conn, user: user, beta: beta} do
      {:ok, view, _html} = live(conn, "/?tab=#{URI.encode_www_form("buy|Контрагенты")}")

      render_change(view, "switch-organization", %{"value" => beta.id})

      workspace = Pulse.Accounts.load_or_create_workspace(user)
      assert workspace.active_organization_id == beta.id
    end

    test "недоступная организация игнорируется", %{conn: conn} do
      outsider = create_actor("admin")

      {:ok, view, _html} = live(conn, "/?tab=#{URI.encode_www_form("buy|Контрагенты")}")

      html = render_change(view, "switch-organization", %{"value" => outsider.organization_id})

      assert html =~ "Альфа-Контрагент"
    end
  end

  describe "справочник без прав" do
    test "кладовщик не видит банки", %{alfa: alfa} do
      user = create_user()
      create_membership(user, alfa, "storekeeper")
      conn = log_in_user(build_conn(), user)

      {:ok, view, _html} = live(conn, "/?tab=#{URI.encode_www_form("bank|Банки")}")

      refute render(view) =~ "Халык Банк"
      assert has_element?(view, "#ws-view")
    end
  end

  defp org_id(view, name) do
    view
    |> element("#org-switch option", name)
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.attribute("value")
    |> List.first()
  end

  defp list(resource, actor) do
    assert {:ok, records} = Ash.read(resource, actor: actor, tenant: actor.organization_id)
    records
  end
end
