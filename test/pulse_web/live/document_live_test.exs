defmodule PulseWeb.DocumentLiveTest do
  @moduledoc """
  Документы в рабочей области: журнал, форма, проведение и отмена.

  Критерий этапа 3: сценарий «хаб → журнал → создать → провести»
  проходит целиком через интерфейс.
  """
  use PulseWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Pulse.Factory
  require Ash.Query

  alias Pulse.Core
  alias Pulse.Purchasing
  alias Pulse.Sales

  @receipts_tab "buy|Поступления ТМЗ и услуг"
  @shipments_tab "sell|Реализации ТМЗ и услуг"

  setup do
    seed_default_permissions!()
    seed_chart_of_accounts!()

    organization = create_organization(%{name: "Документы-Орг"})
    user = create_user()
    create_membership(user, organization, "admin")

    actor =
      Core.Actor.build(
        user,
        [%{organization_id: organization.id, role: "admin"}],
        organization.id
      )

    warehouse = create_warehouse(actor)
    counterparty = create_counterparty(actor)
    nomenclature = create_nomenclature(actor, %{name: "Товар-Док"})

    %{
      conn: log_in_user(build_conn(), user),
      user: user,
      organization: organization,
      actor: actor,
      warehouse: warehouse,
      counterparty: counterparty,
      nomenclature: nomenclature
    }
  end

  describe "журнал документов" do
    test "показывает проведённый документ и его статус", context do
      %{conn: conn, actor: actor} = context

      document = create_receipt(context)

      {:ok, _posted} =
        Pulse.Accounting.Posting.post(document, actor, Pulse.Posting.PurchasingReceipt)

      {:ok, view, _html} = live(conn, tab(@receipts_tab))

      html = render(view)

      assert html =~ "Проведен"
      assert has_element?(view, "#journal-grid")
    end

    test "проведённый документ открывается и показывает движения", context do
      %{conn: conn, actor: actor} = context

      document = create_receipt(context)

      {:ok, _posted} =
        Pulse.Accounting.Posting.post(document, actor, Pulse.Posting.PurchasingReceipt)

      {:ok, view, _html} = live(conn, tab(@receipts_tab))

      html = view |> element("tr[phx-value-id='#{document.id}']") |> render_click()

      assert html =~ "Движения ТМЗ"
      assert has_element?(view, "#document-movements")
      assert has_element?(view, "#unpost-document")
    end
  end

  describe "проведение через интерфейс" do
    test "проведение создаёт движения и меняет статус", context do
      %{conn: conn, actor: actor} = context

      document = create_receipt(context)

      {:ok, view, _html} = live(conn, tab(@receipts_tab))
      view |> element("tr[phx-value-id='#{document.id}']") |> render_click()

      assert has_element?(view, "#post-document")

      html = view |> element("#post-document") |> render_click()

      assert html =~ "Проведен"
      assert html =~ "Движения ТМЗ"

      reloaded = reload(Purchasing.Receipt, document.id, actor)
      assert reloaded.status == :posted
      assert length(stock_movements(reloaded)) == 1
    end

    test "отмена проведения удаляет движения", context do
      %{conn: conn, actor: actor} = context

      document = create_receipt(context)

      {:ok, _posted} =
        Pulse.Accounting.Posting.post(document, actor, Pulse.Posting.PurchasingReceipt)

      {:ok, view, _html} = live(conn, tab(@receipts_tab))
      view |> element("tr[phx-value-id='#{document.id}']") |> render_click()

      html = view |> element("#unpost-document") |> render_click()

      assert html =~ "Не проведен"

      reloaded = reload(Purchasing.Receipt, document.id, actor)
      assert reloaded.status == :draft
      assert stock_movements(reloaded) == []
    end

    test "ошибка проведения показывается в уведомлении", context do
      %{conn: conn} = context

      # Реализация без остатка: проведение отклоняется с понятным текстом.
      document = create_shipment(context)

      {:ok, view, _html} = live(conn, tab(@shipments_tab))
      view |> element("tr[phx-value-id='#{document.id}']") |> render_click()

      html = view |> element("#post-document") |> render_click()

      assert html =~ "недостаточно ТМЗ"
    end

    test "сквозной сценарий: поступление → реализация", context do
      %{conn: conn, actor: actor, warehouse: warehouse, nomenclature: nomenclature} = context

      receipt = create_receipt(context)

      {:ok, view, _html} = live(conn, tab(@receipts_tab))
      view |> element("tr[phx-value-id='#{receipt.id}']") |> render_click()
      view |> element("#post-document") |> render_click()

      shipment = create_shipment(context, quantity: "4")

      {:ok, view2, _html} = live(conn, tab(@shipments_tab))
      view2 |> element("tr[phx-value-id='#{shipment.id}']") |> render_click()
      html = view2 |> element("#post-document") |> render_click()

      assert html =~ "Проведен"

      posted_shipment = reload(Sales.Shipment, shipment.id, actor)
      assert posted_shipment.status == :posted

      balance = balance(actor, warehouse.id, nomenclature.id)
      assert Decimal.to_float(balance.quantity) == 6
      assert Decimal.to_float(balance.cost) == 6000
    end
  end

  defp tab(id), do: "/?tab=" <> URI.encode_www_form(id)

  defp create_receipt(context, opts \\ []) do
    %{actor: actor, counterparty: counterparty, warehouse: warehouse, nomenclature: nomenclature} =
      context

    quantity = Keyword.get(opts, :quantity, "10")
    price = Keyword.get(opts, :price, "1000")

    {:ok, document} =
      Purchasing.Receipt
      |> Ash.Changeset.for_create(:create, %{
        doc_date: ~D[2026-10-20],
        number: "П-#{System.unique_integer([:positive])}",
        counterparty_id: counterparty.id,
        warehouse_id: warehouse.id
      })
      |> Ash.Changeset.set_tenant(actor.organization_id)
      |> Ash.create(actor: actor)

    add_line(Purchasing.ReceiptLine, document, nomenclature.id, quantity, price)
    reload(Purchasing.Receipt, document.id, actor)
  end

  defp create_shipment(context, opts \\ []) do
    %{actor: actor, counterparty: counterparty, warehouse: warehouse, nomenclature: nomenclature} =
      context

    quantity = Keyword.get(opts, :quantity, "4")
    price = Keyword.get(opts, :price, "1500")

    {:ok, document} =
      Sales.Shipment
      |> Ash.Changeset.for_create(:create, %{
        doc_date: ~D[2026-10-20],
        number: "Р-#{System.unique_integer([:positive])}",
        counterparty_id: counterparty.id,
        warehouse_id: warehouse.id
      })
      |> Ash.Changeset.set_tenant(actor.organization_id)
      |> Ash.create(actor: actor)

    add_line(Sales.ShipmentLine, document, nomenclature.id, quantity, price)
    reload(Sales.Shipment, document.id, actor)
  end

  defp add_line(resource, document, nomenclature_id, quantity, price) do
    quantity = Decimal.new(quantity)
    price = Decimal.new(price)

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

  # Движения ТМЗ: документы пишут ещё и в регистры расчётов.
  defp stock_movements(document) do
    document
    |> Pulse.Accounting.Posting.movements()
    |> Enum.filter(&match?(%Pulse.Ledger.StockMovement{}, &1))
  end

  defp balance(actor, warehouse_id, nomenclature_id) do
    context = Pulse.Posting.Context.build(%{organization_id: actor.organization_id}, actor)
    Pulse.Posting.Stock.balance(context, warehouse_id, nomenclature_id, ~D[2026-12-31])
  end
end
