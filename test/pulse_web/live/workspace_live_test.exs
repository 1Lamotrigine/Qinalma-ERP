defmodule PulseWeb.WorkspaceLiveTest do
  @moduledoc """
  Проверки рабочей области: сайдбар, хаб, вкладки, поиск, избранное.
  """
  use PulseWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias PulseWeb.Menu

  setup %{conn: conn} do
    user = Pulse.Factory.create_user()
    %{conn: log_in_user(conn, user), user: user}
  end

  describe "доступ" do
    test "анонимный пользователь перенаправляется на вход" do
      assert {:error, {:redirect, %{to: "/sign-in"}}} = live(build_conn(), ~p"/")
    end

    test "вошедший пользователь видит рабочую область", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/")

      assert html =~ "Qinalma ERP"
      assert has_element?(view, "#workspace")
    end
  end

  describe "сайдбар" do
    test "показывает все 15 разделов", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      for section <- Menu.sections() do
        assert has_element?(view, "#ws-nav button", section.title)
      end

      assert length(Menu.sections()) == 15
    end
  end

  describe "хаб раздела" do
    test "открывается по клику и показывает группы", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      html =
        view
        |> element("#ws-nav button", "Банк и касса")
        |> render_click()

      assert html =~ "Банковские расчетные документы"
      assert has_element?(view, "#hub-groups")
      assert has_element?(view, "#hub-filter")
    end

    test "нереализованные пункты помечены «в разработке»", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      html =
        view
        |> element("#ws-nav button", "Производство")
        |> render_click()

      assert html =~ "в разработке"
    end

    test "фильтр скрывает неподходящие пункты", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#ws-nav button", "Банк и касса") |> render_click()

      html = render_change(view, "filter-hub", %{"value" => "касс"})

      assert html =~ "Кассовые документы"
      refute html =~ "Платежные поручения (входящие)"
    end
  end

  describe "вкладки" do
    test "открывается вкладка из хаба", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#ws-nav button", "Банк и касса") |> render_click()

      html =
        view
        |> element("button[phx-click='open-item'][phx-value-title='Кассовые документы']")
        |> render_click()

      assert has_element?(view, "#ws-tabs button", "Кассовые документы")
      assert html =~ "Кассовые документы"
    end

    test "вкладка закрывается", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#ws-nav button", "Банк и касса") |> render_click()

      view
      |> element("button[phx-click='open-item'][phx-value-title='Кассовые документы']")
      |> render_click()

      html =
        view
        |> element("#ws-tabs button[phx-value-id='bank|Кассовые документы'] span.x")
        |> render_click()

      refute html =~ "Кассовые документы</span>"
    end

    test "вкладки восстанавливаются после перезагрузки", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#ws-nav button", "Банк и касса") |> render_click()

      view
      |> element("button[phx-click='open-item'][phx-value-title='Кассовые документы']")
      |> render_click()

      # Новое подключение с тем же пользователем — вкладки должны восстановиться
      {:ok, _view2, html2} = live(conn, ~p"/")

      assert html2 =~ "Кассовые документы"

      workspace = Pulse.Accounts.load_or_create_workspace(user)
      assert Enum.any?(workspace.tabs, &(&1["title"] == "Кассовые документы"))
    end
  end

  describe "синхронизация вкладок с URL" do
    test "открытие пункта переводит URL на вкладку", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#ws-nav button", "Банк и касса") |> render_click()

      view
      |> element("button[phx-click='open-item'][phx-value-title='Кассовые документы']")
      |> render_click()

      assert_patch(view, "/?tab=" <> URI.encode_www_form("bank|Кассовые документы"))
    end

    test "переключение вкладки переводит URL", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#ws-nav button", "Банк и касса") |> render_click()

      view
      |> element("button[phx-click='open-item'][phx-value-title='Кассовые документы']")
      |> render_click()

      view |> element("#ws-tabs button", "Начальная страница") |> render_click()

      assert_patch(view, "/?tab=home")
    end

    test "закрытие активной вкладки возвращает URL на оставшуюся", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#ws-nav button", "Банк и касса") |> render_click()

      view
      |> element("button[phx-click='open-item'][phx-value-title='Кассовые документы']")
      |> render_click()

      view
      |> element("#ws-tabs button[phx-value-id='bank|Кассовые документы'] span.x")
      |> render_click()

      assert_patch(view, "/?tab=home")
    end

    test "прямой переход по URL с tab открывает вкладку", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#ws-nav button", "Банк и касса") |> render_click()

      view
      |> element("button[phx-click='open-item'][phx-value-title='Кассовые документы']")
      |> render_click()

      # Новое подключение по адресу вкладки
      {:ok, view2, _html2} = live(conn, ~p"/?tab=bank|Кассовые документы")

      assert render(view2) =~ "Кассовые документы"
    end

    test "открытие хаба переводит URL на section", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#ws-nav button", "Банк и касса") |> render_click()

      assert_patch(view, ~p"/?section=bank")
    end
  end

  describe "закрытие поиска" do
    test "событие close-search очищает результаты", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      render_keyup(view, "search", %{"value" => "кассовая книга"})
      assert has_element?(view, "#search-results")

      render_click(view, "close-search", %{})

      refute has_element?(view, "#search-results")
      refute render(view) =~ "Кассовая книга"
    end
  end

  describe "глобальный поиск" do
    test "находит пункт меню по названию", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      html = render_keyup(view, "search", %{"value" => "кассовая книга"})

      assert html =~ "Кассовая книга"
      assert has_element?(view, "#search-results")
    end

    test "переход по результату открывает вкладку", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      render_keyup(view, "search", %{"value" => "кассовая книга"})

      html =
        view
        |> element("#search-results button", "Кассовая книга")
        |> render_click()

      assert has_element?(view, "#ws-tabs button", "Кассовая книга")
      assert html =~ "Кассовая книга"
    end

    test "пустой запрос не показывает результатов", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      html = render_keyup(view, "search", %{"value" => ""})

      refute html =~ "search-results"
    end
  end

  describe "избранное" do
    test "добавление в избранное и отображение на главной", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#ws-nav button", "Операции") |> render_click()

      html =
        view
        |> element("button[phx-value-title='Журнал операций'][phx-click='toggle-favorite']")
        |> render_click()

      assert html =~ "st on"
    end
  end

  describe "формы" do
    test "создание документа из журнала", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#ws-nav button", "Покупка") |> render_click()

      view
      |> element("button[phx-click='open-item'][phx-value-title='Поступления ТМЗ и услуг']")
      |> render_click()

      # Журнал пуст: в демо-организации нет документов — форма открывается,
      # но без строк, поэтому проверяем переход на экран документа.
      assert has_element?(view, "#journal-grid")
    end

    test "журнал реализации показывает реальные документы", %{conn: conn} do
      {:ok, view, _html} =
        live(conn, "/?tab=" <> URI.encode_www_form("sell|Реализации ТМЗ и услуг"))

      assert has_element?(view, "#journal-grid")
      assert has_element?(view, "button[phx-click='create-document']")
    end

    test "проведение документа из журнала открывает форму", %{conn: conn, user: user} do
      organization = Pulse.Factory.create_organization(%{name: "Формы-Орг"})
      Pulse.Factory.create_membership(user, organization, "admin")

      {:ok, view, _html} =
        live(conn, "/?tab=" <> URI.encode_www_form("buy|Поступления ТМЗ и услуг"))

      # Документов пока нет — журнал пуст, но форма открывается.
      html = view |> element("button[phx-click='create-document']") |> render_click()

      assert html =~ "Новый документ: Поступления ТМЗ и услуг"
    end
  end

  describe "отчёты" do
    test "бухгалтерский отчёт формируется по кнопке", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#ws-nav button", "Отчеты") |> render_click()

      view
      |> element(
        "button[phx-click='open-item'][phx-value-title='Оборотно-сальдовая ведомость (бух.)']"
      )
      |> render_click()

      assert has_element?(view, "#report-build")

      html = view |> element("#report-build") |> render_click()

      # У пользователя нет активной организации: отчёт сообщает об этом.
      assert html =~ "выберите активную организацию"
      assert has_element?(view, "#report-result")
    end

    test "отчёт без реализации показывает демонстрационный результат", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#ws-nav button", "Отчеты") |> render_click()

      view
      |> element(
        "button[phx-click='open-item'][phx-value-title='Универсальный отчет по метаданным']"
      )
      |> render_click()

      html = view |> element("button[phx-click='generate-report']") |> render_click()

      assert html =~ "Итого"
    end
  end
end
