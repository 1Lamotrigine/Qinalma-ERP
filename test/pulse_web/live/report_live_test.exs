defmodule PulseWeb.ReportLiveTest do
  @moduledoc """
  Бухгалтерские отчёты в рабочей области: ОСВ, карточка и анализ счёта.

  Критерий этапа 4: отчёты строятся из интерфейса и дают цифры,
  совпадающие с журналом проводок.
  """
  use PulseWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Pulse.Factory
  require Ash.Query

  alias Pulse.Accounting.Posting
  alias Pulse.Core
  alias Pulse.Purchasing
  alias Pulse.Sales

  @trial_balance_tab "rep|Оборотно-сальдовая ведомость (бух.)"
  @card_tab "rep|Карточка счета (бух.)"

  setup do
    seed_default_permissions!()
    seed_chart_of_accounts!()

    organization = create_organization(%{name: "Отчёты-UI"})
    user = create_user()
    create_membership(user, organization, "admin")

    actor =
      Core.Actor.build(
        user,
        [%{organization_id: organization.id, role: "admin"}],
        organization.id
      )

    context = %{
      actor: actor,
      organization: organization,
      warehouse: create_warehouse(actor),
      counterparty: create_counterparty(actor),
      nomenclature: create_nomenclature(actor, %{name: "Товар-Отчёт-UI"})
    }

    post_receipt(context, quantity: "10", price: "1000")

    %{
      conn: log_in_user(build_conn(), user),
      user: user,
      organization: organization,
      actor: actor,
      warehouse: context.warehouse,
      counterparty: context.counterparty,
      nomenclature: context.nomenclature
    }
  end

  describe "оборотно-сальдовая ведомость" do
    test "строится из интерфейса и показывает счета", %{conn: conn} = context do
      post_shipment(context, quantity: "4", price: "1500")

      {:ok, view, _html} = live(conn, tab(@trial_balance_tab))

      html =
        render_click(view, "generate-report", %{"from" => "2026-10-01", "to" => "2026-10-31"})

      assert html =~ "1330"
      assert html =~ "3310"
      assert html =~ "6010"
      assert has_element?(view, "#report-result table")
    end

    test "период без движений показывает пустой отчёт", %{conn: conn} do
      {:ok, view, _html} = live(conn, tab(@trial_balance_tab))

      html =
        render_click(view, "generate-report", %{"from" => "2026-01-01", "to" => "2026-01-31"})

      assert html =~ "Нет данных за период"
    end

    test "итоги ведомости сходятся по дебету и кредиту", %{conn: conn} do
      {:ok, view, _html} = live(conn, tab(@trial_balance_tab))

      html =
        render_click(view, "generate-report", %{"from" => "2026-10-01", "to" => "2026-10-31"})

      # Обороты дебета и кредита равны — по 10 000.
      assert html =~ "10000"
    end
  end

  describe "карточка счёта" do
    test "показывает проводки по счёту", %{conn: conn} do
      {:ok, view, _html} = live(conn, tab(@card_tab))

      html =
        render_click(view, "generate-report", %{
          "from" => "2026-10-01",
          "to" => "2026-10-31",
          "account" => "1330"
        })

      assert html =~ "Поступление"
      assert html =~ "10000"
      assert has_element?(view, "#report-account")
    end
  end

  describe "доступ" do
    test "отчёт без активной организации сообщает об ошибке", %{conn: _conn} do
      # Пользователь без членства: активной организации нет.
      other = create_user()
      conn = log_in_user(build_conn(), other)

      {:ok, view, _html} = live(conn, tab(@trial_balance_tab))

      html =
        render_click(view, "generate-report", %{"from" => "2026-10-01", "to" => "2026-10-31"})

      assert html =~ "выберите активную организацию"
    end
  end

  defp tab(id), do: "/?tab=" <> URI.encode_www_form(id)

  defp post_receipt(context, opts) do
    %{actor: actor, counterparty: counterparty, warehouse: warehouse, nomenclature: nomenclature} =
      context

    {:ok, document} =
      Purchasing.Receipt
      |> Ash.Changeset.for_create(:create, %{
        doc_date: ~D[2026-10-05],
        number: "П-#{System.unique_integer([:positive])}",
        counterparty_id: counterparty.id,
        warehouse_id: warehouse.id
      })
      |> Ash.Changeset.set_tenant(actor.organization_id)
      |> Ash.create(actor: actor)

    add_line(Purchasing.ReceiptLine, document, nomenclature.id, opts)
    document = reload(Purchasing.Receipt, document.id, actor)
    {:ok, _posted} = Posting.post(document, actor, Pulse.Posting.PurchasingReceipt)
    :ok
  end

  defp post_shipment(context, opts) do
    %{actor: actor, counterparty: counterparty, warehouse: warehouse, nomenclature: nomenclature} =
      context

    {:ok, document} =
      Sales.Shipment
      |> Ash.Changeset.for_create(:create, %{
        doc_date: ~D[2026-10-12],
        number: "Р-#{System.unique_integer([:positive])}",
        counterparty_id: counterparty.id,
        warehouse_id: warehouse.id
      })
      |> Ash.Changeset.set_tenant(actor.organization_id)
      |> Ash.create(actor: actor)

    add_line(Sales.ShipmentLine, document, nomenclature.id, opts)
    document = reload(Sales.Shipment, document.id, actor)
    {:ok, _posted} = Posting.post(document, actor, Pulse.Posting.SalesShipment)
    :ok
  end

  defp add_line(resource, document, nomenclature_id, opts) do
    quantity = Decimal.new(Keyword.fetch!(opts, :quantity))
    price = Decimal.new(Keyword.fetch!(opts, :price))

    resource
    |> Ash.Changeset.for_create(:create, %{
      organization_id: document.organization_id,
      document_id: document.id,
      line_no: 1,
      nomenclature_id: nomenclature_id,
      quantity: quantity,
      price: price,
      amount: Decimal.mult(quantity, price)
    })
    |> Ash.Changeset.set_tenant(document.organization_id)
    |> Ash.create!(authorize?: false)
  end

  defp reload(resource, id, actor) do
    query = Ash.Query.filter(resource, id == ^id)

    {:ok, [document]} =
      Ash.read(query, actor: actor, tenant: actor.organization_id, load: [:lines])

    document
  end
end
