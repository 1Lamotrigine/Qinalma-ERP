defmodule PulseWeb.PayrollLiveTest do
  @moduledoc """
  Кадры и зарплата в рабочей области (этап 8).

  Критерии этапа: кадровые документы проводятся и влияют на расчёт;
  начисление строится по сотрудникам; зарплата доступна ролям;
  справочники физлиц и сотрудников ведутся из интерфейса.
  """
  use PulseWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Pulse.Factory

  alias Pulse.Core

  setup do
    seed_default_permissions!()
    seed_chart_of_accounts!()
    seed_statutory_rates!()

    organization = create_organization(%{name: "Зарплата-UI"})
    user = create_user()
    create_membership(user, organization, "admin")

    actor =
      Core.Actor.build(
        user,
        [%{organization_id: organization.id, role: "admin"}],
        organization.id
      )

    %{
      conn: log_in_user(build_conn(), user),
      user: user,
      organization: organization,
      actor: actor
    }
  end

  describe "справочники кадров" do
    test "физлицо создаётся через форму", %{conn: conn} do
      {:ok, view, _html} = live(conn, tab("hr|Физические лица"))

      render_click(view, "create-document", %{"title" => "Физические лица"})
      assert has_element?(view, "#catalog-form")

      html =
        view
        |> form("#catalog-form", %{
          "catalog" => %{
            "last_name" => "Тестов",
            "first_name" => "Пётр",
            "iin" => "880101300777"
          }
        })
        |> render_submit()

      assert html =~ "Тестов"
    end

    test "сотрудник виден в журнале с должностью", %{conn: conn, actor: actor} do
      position = create_position(actor, %{name: "Инженер"})
      create_employee(actor, %{position_id: position.id, salary: Decimal.new("250000")})

      {:ok, _view, html} = live(conn, tab("hr|Сотрудники"))

      assert html =~ "Инженер"
    end
  end

  describe "кадровые документы" do
    test "приём проводится и создаёт сотрудника", %{conn: conn, actor: actor, organization: org} do
      person = create_person(actor, %{last_name: "Принятов"})
      position = create_position(actor, %{name: "Кладовщик"})

      {:ok, view, _html} = live(conn, tab("hr|Приемы на работу в организации"))

      render_click(view, "create-document", %{"title" => "Приемы на работу в организации"})
      assert has_element?(view, "#catalog-form")

      view
      |> form("#catalog-form", %{
        "catalog" => %{
          "doc_date" => "2026-09-01",
          "number" => "ПР-UI-1",
          "kind" => "hiring",
          "person_id" => person.id,
          "position_id" => position.id,
          "salary" => "300000"
        }
      })
      |> render_submit()

      # Документ появился в журнале и его можно провести из строки.
      assert render(view) =~ "ПР-UI-1"

      [document] =
        Pulse.HR.CadreDocument
        |> Ash.read!(tenant: org.id, authorize?: false)

      assert {:ok, posted} = Pulse.HR.Posting.post(document, actor)
      assert posted.status == :posted

      [employee] = Pulse.HR.Employee |> Ash.read!(tenant: org.id, authorize?: false)
      assert Decimal.equal?(employee.salary, Decimal.new("300000"))
    end
  end

  describe "начисление зарплаты" do
    test "ведомость строится по сотрудникам из интерфейса", %{conn: conn, actor: actor} do
      create_employee(actor, %{salary: Decimal.new("200000")})

      {:ok, view, _html} = live(conn, tab("pay|Начисления зарплаты сотрудникам организаций"))

      html =
        render_click(view, "create-document", %{
          "title" => "Начисления зарплаты сотрудникам организаций"
        })

      assert html =~ "Ведомость заполнена"
      assert has_element?(view, "#document-lines")
    end

    test "отчёт «Расчетные ведомости» показывает начисления", %{
      conn: conn,
      actor: actor,
      organization: org
    } do
      create_employee(actor, %{salary: Decimal.new("200000")})
      {:ok, accrual} = Pulse.Payroll.Accruals.build(org.id, actor, ~D[2026-10-31], ~D[2026-10-01])
      loaded = Pulse.Payroll.Accruals.load(accrual.id, org.id)
      {:ok, _posted} = Pulse.Accounting.Posting.post(loaded, actor, Pulse.Posting.PayrollAccrual)

      {:ok, view, _html} = live(conn, tab("pay|Расчетные ведомости организаций"))

      html =
        render_click(view, "generate-report", %{"from" => "2026-10-01", "to" => "2026-10-31"})

      assert html =~ "Начислено"
      assert has_element?(view, "#report-result table")
    end
  end

  describe "доступ" do
    test "без прав на зарплату журнал пуст", %{organization: organization} do
      # Роль кладовщика не имеет прав на зарплату.
      other = create_user()
      create_membership(other, organization, "storekeeper")
      conn = log_in_user(build_conn(), other)

      {:ok, _view, html} = live(conn, tab("pay|Начисления зарплаты сотрудникам организаций"))

      refute html =~ "ЗП-"
    end
  end

  defp tab(id), do: "/?tab=" <> URI.encode_www_form(id)
end
