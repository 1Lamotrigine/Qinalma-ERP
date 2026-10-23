defmodule Pulse.Tax.InvoicesTest do
  @moduledoc """
  Счета-фактуры и выгрузка XML (этап 7).

  Критерии этапа: счёт-фактура формируется из документа-основания,
  печатается и выгружается в XML; ставка НДС берётся из
  законодательных параметров на дату документа.
  """
  use Pulse.DataCase, async: true

  import Pulse.Factory
  require Ash.Query

  alias Pulse.Accounting.Posting
  alias Pulse.Core
  alias Pulse.Purchasing
  alias Pulse.Sales
  alias Pulse.Tax.Esf
  alias Pulse.Tax.Invoices

  setup do
    seed_default_permissions!()
    seed_chart_of_accounts!()

    create_statutory_rate(%{
      code: "vat_rate",
      value: Decimal.new("16"),
      valid_from: ~D[2026-01-01]
    })

    organization = create_organization(%{name: "Налоги-Орг", bin: "190140012345"})
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
      counterparty: create_counterparty(actor, %{name: "ТОО «Покупатель»", bin: "120140012345"}),
      warehouse: create_warehouse(actor),
      nomenclature: create_nomenclature(actor, %{name: "Товар-НДС", price: Decimal.new("1000")})
    }

    # Остаток, чтобы реализация могла провестись.
    _ = post_receipt(context, quantity: "100", price: "500")

    context
  end

  describe "формирование из документа-основания" do
    test "выданный счёт-фактура по реализации", context do
      shipment = post_shipment(context, quantity: "10", price: "1000")

      assert {:ok, invoice} = Invoices.create_from_document(shipment, :issued)

      assert invoice.direction == :issued
      assert invoice.invoice_date == ~D[2026-10-10]
      assert invoice.counterparty_id == context.counterparty.id
      assert invoice.document_id == shipment.id

      # Строки дают 10 000 — это сумма с НДС; НДС считается по ставке
      # 16 % из законодательных параметров на дату документа.
      assert Decimal.equal?(invoice.vat_rate, Decimal.new("16"))
      assert Decimal.equal?(invoice.vat_amount, Decimal.new("1379.31"))
      assert Decimal.equal?(invoice.amount, Decimal.new("10000"))
    end

    test "полученный счёт-фактура по поступлению", context do
      receipt = post_receipt(context, quantity: "5", price: "2000")

      assert {:ok, invoice} = Invoices.create_from_document(receipt, :received)
      assert invoice.direction == :received
      assert invoice.number =~ "СФ-П"
    end

    test "повторное формирование не создаёт дубль", context do
      shipment = post_shipment(context, quantity: "1", price: "1000")

      assert {:ok, first} = Invoices.create_from_document(shipment, :issued)
      assert {:ok, second} = Invoices.create_from_document(shipment, :issued)
      assert first.id == second.id
    end

    test "без ставки НДС счёт-фактура не формируется", context do
      # Удаляем единственную ставку — система должна явно отказать.
      Pulse.Tax.StatutoryRate
      |> Ash.read!(authorize?: false)
      |> Enum.each(fn rate ->
        rate |> Ash.Changeset.for_destroy(:destroy) |> Ash.destroy!(authorize?: false)
      end)

      shipment = post_shipment(context, quantity: "1", price: "1000")

      assert {:error, message} = Invoices.create_from_document(shipment, :issued)
      assert message =~ "vat_rate"
    end
  end

  describe "итоги журнала" do
    test "считает суммы с НДС, без НДС и НДС", context do
      shipment = post_shipment(context, quantity: "10", price: "1000")
      {:ok, _invoice} = Invoices.create_from_document(shipment, :issued)

      invoices = Invoices.list(context.organization.id, :issued, ~D[2026-10-01], ~D[2026-10-31])
      totals = Invoices.totals(invoices)

      assert Decimal.equal?(totals.gross, Decimal.new("10000"))
      assert Decimal.equal?(totals.vat, Decimal.new("1379.31"))
      assert Decimal.equal?(totals.net, Decimal.new("8620.69"))
    end
  end

  describe "выгрузка XML" do
    test "XML содержит реквизиты и суммы", context do
      shipment = post_shipment(context, quantity: "10", price: "1000")
      {:ok, invoice} = Invoices.create_from_document(shipment, :issued)

      {organization, counterparty} = {context.organization, context.counterparty}
      xml = Esf.to_xml(invoice, organization, counterparty)

      assert xml =~ ~s(<?xml version="1.0" encoding="UTF-8"?>)
      assert xml =~ "<number>#{invoice.number}</number>"
      assert xml =~ "Налоги-Орг"
      assert xml =~ "ТОО «Покупатель»"
      assert xml =~ "<vatRate>16.00</vatRate>"
      assert xml =~ "<vatAmount>1379.31</vatAmount>"
    end

    test "имя файла безопасно", context do
      shipment = post_shipment(context, quantity: "1", price: "1000")
      {:ok, invoice} = Invoices.create_from_document(shipment, :issued)

      filename = Esf.filename(invoice)
      assert String.ends_with?(filename, ".xml")
      refute filename =~ ~r/[\s\/]/
    end
  end

  # --- вспомогательное -------------------------------------------------------

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
    document = reload(Sales.Shipment, document.id, actor.organization_id)
    {:ok, posted} = Posting.post(document, actor, Pulse.Posting.SalesShipment)
    posted
  end

  defp post_receipt(context, opts) do
    %{actor: actor, counterparty: counterparty, warehouse: warehouse, nomenclature: nomenclature} =
      context

    {:ok, document} =
      Purchasing.Receipt
      |> Ash.Changeset.for_create(:create, %{
        doc_date: ~D[2026-10-10],
        number: "П-#{System.unique_integer([:positive])}",
        counterparty_id: counterparty.id,
        warehouse_id: warehouse.id
      })
      |> Ash.Changeset.set_tenant(actor.organization_id)
      |> Ash.create(actor: actor)

    add_line(Purchasing.ReceiptLine, document, nomenclature.id, opts)
    document = reload(Purchasing.Receipt, document.id, actor.organization_id)
    {:ok, posted} = Posting.post(document, actor, Pulse.Posting.PurchasingReceipt)
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

  defp reload(resource, id, organization_id) do
    query = Ash.Query.filter(resource, id == ^id)

    {:ok, [document]} =
      Ash.read(query, tenant: organization_id, authorize?: false, load: [:lines])

    document
  end
end
