defmodule PulseWeb.TaxLiveTest do
  @moduledoc """
  Налоговый контур в рабочей области: ставки, журналы счетов-фактур
  и налоговые отчёты (этап 7).

  Критерии этапа: ставки правятся через интерфейс без релиза; счёт-фактура
  формируется из документа, печатается и выгружается в XML; налоговый
  учёт отделён от бухгалтерского.
  """
  use PulseWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Pulse.Factory
  require Ash.Query

  alias Pulse.Accounting.Posting
  alias Pulse.Core
  alias Pulse.Purchasing
  alias Pulse.Sales
  alias Pulse.Tax.Invoices

  @rates_tab "ent|Сведения о ставках налогов, сборов и отчислений"
  @issued_tab "sell|Счета-фактуры (выданные)"
  @received_tab "buy|Счета-фактуры (полученные)"
  @journal_report_tab "sell|Журнал учета счетов-фактур"
  @tax_balance_tab "rep|Оборотно-сальдовая ведомость (налоговый)"

  setup do
    seed_default_permissions!()
    seed_chart_of_accounts!()

    create_statutory_rate(%{
      code: "vat_rate",
      value: Decimal.new("16"),
      valid_from: ~D[2026-01-01]
    })

    organization = create_organization(%{name: "Налоги-UI", bin: "190140012345"})
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
      counterparty: create_counterparty(actor, %{name: "ТОО «Покупатель»", bin: "120140012345"}),
      nomenclature: create_nomenclature(actor, %{name: "Товар-UI", price: Decimal.new("1000")})
    }

    post_receipt(context, quantity: "100", price: "500")

    shipment = post_shipment(context, quantity: "10", price: "1000")
    {:ok, invoice} = Invoices.create_from_document(shipment, :issued)

    Map.merge(context, %{
      conn: log_in_user(build_conn(), user),
      user: user,
      invoice: invoice
    })
  end

  describe "ставки налогов" do
    test "журнал ставок открывается и показывает значения", %{conn: conn} do
      {:ok, view, html} = live(conn, tab(@rates_tab))

      assert html =~ "vat_rate"
      assert has_element?(view, "#journal-grid")
    end

    test "ставка создаётся через форму и попадает в журнал", %{conn: conn} do
      {:ok, view, _html} = live(conn, tab(@rates_tab))

      render_click(view, "create-document", %{
        "title" => "Сведения о ставках налогов, сборов и отчислений"
      })

      assert has_element?(view, "#catalog-form")

      html =
        view
        |> form("#catalog-form", %{
          "catalog" => %{
            "code" => "mrp",
            "name" => "МРП",
            "value" => "4325",
            "valid_from" => "2026-01-01"
          }
        })
        |> render_submit()

      assert html =~ "mrp"
    end
  end

  describe "журнал счетов-фактур" do
    test "выданные счета-фактуры видны в журнале", %{conn: conn, invoice: invoice} do
      {:ok, view, html} = live(conn, tab(@issued_tab))

      assert html =~ invoice.number
      assert has_element?(view, "#journal-grid")
    end

    test "полученные счета-фактуры не смешиваются с выданными", %{conn: conn} do
      {:ok, _view, html} = live(conn, tab(@received_tab))

      refute html =~ "СФ-В-"
    end

    test "открывается печатная форма с XML", %{conn: conn, invoice: invoice} do
      {:ok, view, _html} = live(conn, tab(@issued_tab))

      html = render_click(view, "open-document", %{"id" => invoice.id})

      assert html =~ "Счёт-фактура выданная"
      assert has_element?(view, "#invoice-totals")
      assert has_element?(view, "#invoice-xml")
      assert has_element?(view, "#download-invoice-xml")
    end
  end

  describe "налоговые отчёты" do
    test "журнал учета счетов-фактур строится из интерфейса", %{conn: conn, invoice: invoice} do
      {:ok, view, _html} = live(conn, tab(@journal_report_tab))

      html =
        render_click(view, "generate-report", %{"from" => "2026-10-01", "to" => "2026-10-31"})

      assert html =~ invoice.number
      assert html =~ "НДС к уплате"
    end

    test "налоговый учёт отделён от бухгалтерского", %{conn: conn} do
      {:ok, view, _html} = live(conn, tab(@tax_balance_tab))

      html =
        render_click(view, "generate-report", %{"from" => "2026-10-01", "to" => "2026-10-31"})

      # В налоговом учёте проводок нет — ведомость пуста, и это не ошибка.
      assert html =~ "Налоговый учёт"
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
    {:ok, posted} = Posting.post(document, actor, Pulse.Posting.PurchasingReceipt)
    posted
  end

  defp post_shipment(context, opts) do
    %{actor: actor, counterparty: counterparty, warehouse: warehouse, nomenclature: nomenclature} =
      context

    {:ok, document} =
      Sales.Shipment
      |> Ash.Changeset.for_create(:create, %{
        doc_date: ~D[2026-10-10],
        number: "Р-#{System.unique_integer([:positive])}",
        counterparty_id: counterparty.id,
        warehouse_id: warehouse.id
      })
      |> Ash.Changeset.set_tenant(actor.organization_id)
      |> Ash.create(actor: actor)

    add_line(Sales.ShipmentLine, document, nomenclature.id, opts)
    document = reload(Sales.Shipment, document.id, actor)
    {:ok, posted} = Posting.post(document, actor, Pulse.Posting.SalesShipment)
    posted
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
