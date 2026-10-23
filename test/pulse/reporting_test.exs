defmodule Pulse.ReportingTest do
  @moduledoc """
  Виджеты начальной страницы и монитор руководителя.

  Критерий этапа 5: виджеты показывают настоящие цифры — остатки денег,
  долги покупателей и поставщиков, продажи за период.
  """
  use Pulse.DataCase, async: true

  import Pulse.Factory
  require Ash.Query

  alias Pulse.Accounting.Posting
  alias Pulse.Core
  alias Pulse.Reporting
  alias Pulse.Sales
  alias Pulse.Treasury

  @date ~D[2026-10-20]

  setup do
    seed_default_permissions!()
    seed_chart_of_accounts!()

    organization = create_organization(%{name: "Показатели-Орг"})
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
      counterparty: create_counterparty(actor),
      supplier: create_counterparty(actor, %{name: "Поставщик-Показатель"}),
      stock_supplier: create_counterparty(actor, %{name: "Складской поставщик"}),
      bank_account: create_bank_account(actor),
      cash_desk: create_cash_desk(actor),
      warehouse: create_warehouse(actor),
      nomenclature: create_nomenclature(actor, %{name: "Товар-Показатель"})
    }

    post_receipt(context, counterparty: context.stock_supplier, amount: "100000")
    context
  end

  describe "виджет денег" do
    test "показывает остатки кассы и банка", context do
      %{organization: organization} = context

      post_bank(context, direction: :receipt, amount: "150000")
      post_cash(context, direction: :receipt, amount: "30000")

      widget = Reporting.cash_widget(organization.id, @date)

      assert decimal(widget.cash) == 30_000
      assert decimal(widget.bank) == 150_000
      assert decimal(widget.total) == 180_000
    end

    test "учитывает списания", context do
      %{organization: organization} = context

      post_bank(context, direction: :receipt, amount: "100000")
      post_bank(context, direction: :expense, amount: "40000")

      widget = Reporting.cash_widget(organization.id, @date)
      assert decimal(widget.bank) == 60_000
    end

    test "пустая организация показывает нули" do
      other = create_actor("admin")
      widget = Reporting.cash_widget(other.organization_id, @date)

      assert decimal(widget.cash) == 0
      assert decimal(widget.bank) == 0
      assert decimal(widget.total) == 0
    end
  end

  describe "виджет покупателей" do
    test "показывает задолженность после реализации", context do
      %{organization: organization} = context

      post_shipment(context, amount: "60000")

      widget = Reporting.customers_widget(organization.id, @date)
      assert decimal(widget.total) == 60_000
    end

    test "оплата уменьшает задолженность", context do
      %{organization: organization} = context

      post_shipment(context, amount: "60000")
      post_bank(context, direction: :receipt, amount: "25000")

      widget = Reporting.customers_widget(organization.id, @date)
      assert decimal(widget.total) == 35_000
    end

    test "показывает авансы полученные", context do
      %{organization: organization} = context

      post_bank(context, direction: :receipt, amount: "50000")

      widget = Reporting.customers_widget(organization.id, @date)
      assert decimal(widget.advance) == 50_000
    end
  end

  describe "виджет поставщиков" do
    test "показывает задолженность перед поставщиком", context do
      %{organization: organization} = context

      # Поступление в setup создало долг перед складским поставщиком.
      widget = Reporting.suppliers_widget(organization.id, @date)
      assert decimal(widget.total) == 100_000
    end
  end

  describe "виджет продаж" do
    test "считает выручку по проводкам счёта 6010", context do
      %{organization: organization} = context

      post_shipment(context, amount: "60000")

      widget = Reporting.sales_widget(organization.id, @date)

      assert decimal(widget.month) == 60_000
      assert decimal(widget.year) == 60_000
      assert decimal(widget.previous_month) == 0
    end

    test "без продаж выручка нулевая", %{organization: organization} do
      widget = Reporting.sales_widget(organization.id, @date)

      assert decimal(widget.month) == 0
      assert decimal(widget.year) == 0
    end
  end

  describe "сводка" do
    test "собирает все виджеты", context do
      %{organization: organization} = context

      post_bank(context, direction: :receipt, amount: "150000")

      dashboard = Reporting.dashboard(organization.id, @date)

      assert dashboard.date == @date
      assert decimal(dashboard.cash.total) == 150_000
      assert is_map(dashboard.customers)
      assert is_map(dashboard.suppliers)
      assert is_map(dashboard.sales)
    end
  end

  # --- построение документов ------------------------------------------------

  defp post_bank(context, opts) do
    %{actor: actor, bank_account: account} = context
    counterparty = Keyword.get(opts, :counterparty, context.counterparty)

    {:ok, document} =
      Treasury.BankDocument
      |> Ash.Changeset.for_create(:create, %{
        doc_date: ~D[2026-10-20],
        number: "Б-#{System.unique_integer([:positive])}",
        direction: Keyword.fetch!(opts, :direction),
        bank_account_id: account.id,
        counterparty_id: counterparty.id,
        amount: Decimal.new(Keyword.fetch!(opts, :amount))
      })
      |> Ash.Changeset.set_tenant(actor.organization_id)
      |> Ash.create(actor: actor)

    {:ok, posted} = Posting.post(document, actor, Pulse.Posting.TreasuryPayment)
    posted
  end

  defp post_cash(context, opts) do
    %{actor: actor, cash_desk: desk, counterparty: counterparty} = context

    {:ok, document} =
      Treasury.CashDocument
      |> Ash.Changeset.for_create(:create, %{
        doc_date: ~D[2026-10-20],
        number: "К-#{System.unique_integer([:positive])}",
        direction: Keyword.fetch!(opts, :direction),
        cash_desk_id: desk.id,
        counterparty_id: counterparty.id,
        amount: Decimal.new(Keyword.fetch!(opts, :amount))
      })
      |> Ash.Changeset.set_tenant(actor.organization_id)
      |> Ash.create(actor: actor)

    {:ok, posted} = Posting.post(document, actor, Pulse.Posting.TreasuryPayment)
    posted
  end

  defp post_receipt(context, opts) do
    %{actor: actor, warehouse: warehouse, nomenclature: nomenclature} = context
    counterparty = Keyword.get(opts, :counterparty, context.supplier)
    amount = Decimal.new(Keyword.fetch!(opts, :amount))
    quantity = Decimal.new(100)

    {:ok, receipt} =
      Pulse.Purchasing.Receipt
      |> Ash.Changeset.for_create(:create, %{
        doc_date: ~D[2026-10-01],
        number: "П-#{System.unique_integer([:positive])}",
        counterparty_id: counterparty.id,
        warehouse_id: warehouse.id
      })
      |> Ash.Changeset.set_tenant(actor.organization_id)
      |> Ash.create(actor: actor)

    Pulse.Purchasing.ReceiptLine
    |> Ash.Changeset.for_create(:create, %{
      organization_id: actor.organization_id,
      document_id: receipt.id,
      line_no: 1,
      nomenclature_id: nomenclature.id,
      quantity: quantity,
      price: Decimal.div(amount, quantity),
      amount: amount
    })
    |> Ash.Changeset.set_tenant(actor.organization_id)
    |> Ash.create!(authorize?: false)

    loaded = reload(Pulse.Purchasing.Receipt, receipt.id, actor)
    {:ok, posted} = Posting.post(loaded, actor, Pulse.Posting.PurchasingReceipt)
    posted
  end

  defp post_shipment(context, opts) do
    %{actor: actor, counterparty: counterparty, warehouse: warehouse, nomenclature: nomenclature} =
      context

    amount = Decimal.new(Keyword.fetch!(opts, :amount))
    quantity = Decimal.new(10)

    {:ok, shipment} =
      Sales.Shipment
      |> Ash.Changeset.for_create(:create, %{
        doc_date: ~D[2026-10-15],
        number: "Р-#{System.unique_integer([:positive])}",
        counterparty_id: counterparty.id,
        warehouse_id: warehouse.id
      })
      |> Ash.Changeset.set_tenant(actor.organization_id)
      |> Ash.create(actor: actor)

    Sales.ShipmentLine
    |> Ash.Changeset.for_create(:create, %{
      organization_id: actor.organization_id,
      document_id: shipment.id,
      line_no: 1,
      nomenclature_id: nomenclature.id,
      quantity: quantity,
      price: Decimal.div(amount, quantity),
      amount: amount
    })
    |> Ash.Changeset.set_tenant(actor.organization_id)
    |> Ash.create!(authorize?: false)

    loaded = reload(Sales.Shipment, shipment.id, actor)
    {:ok, posted} = Posting.post(loaded, actor, Pulse.Posting.SalesShipment)
    posted
  end

  defp reload(resource, id, actor) do
    query = Ash.Query.filter(resource, id == ^id)

    {:ok, [document]} =
      Ash.read(query, actor: actor, tenant: actor.organization_id, load: [:lines])

    document
  end

  defp decimal(value), do: Decimal.to_float(value)
end
