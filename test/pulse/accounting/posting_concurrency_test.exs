defmodule Pulse.Accounting.PostingConcurrencyTest do
  @moduledoc """
  Конкурентность проведения (раздел 10 ТЗ).

  Параллельное проведение расходов по одной номенклатуре не должно
  создавать отрицательный остаток: `pg_advisory_xact_lock` берётся
  в отсортированном порядке, а проверка остатков идёт под блокировкой.
  """
  use Pulse.DataCase, async: false

  import Pulse.Factory
  require Ash.Query

  alias Pulse.Accounting.Posting
  alias Pulse.Core
  alias Pulse.Purchasing
  alias Pulse.Sales

  setup do
    seed_default_permissions!()
    seed_chart_of_accounts!()

    organization = create_organization(%{name: "Поток-Орг"})
    user = create_user()
    create_membership(user, organization, "admin")

    actor =
      Core.Actor.build(
        user,
        [%{organization_id: organization.id, role: "admin"}],
        organization.id
      )

    %{
      actor: actor,
      organization: organization,
      warehouse: create_warehouse(actor),
      counterparty: create_counterparty(actor),
      nomenclature: create_nomenclature(actor, %{name: "Товар-Поток"})
    }
  end

  test "параллельные расходы не создают отрицательный остаток", context do
    %{actor: actor, warehouse: warehouse, nomenclature: nomenclature} = context

    # На складе 10 единиц; восемь параллельных расходов по 2 единицы
    # конкурируют за один и тот же остаток.
    post_receipt(context, "10", "1000")

    shipments =
      for _index <- 1..8 do
        create_shipment(context, "2", "1500")
      end

    results =
      shipments
      |> Task.async_stream(
        fn shipment -> Posting.post(shipment, actor, Pulse.Posting.SalesShipment) end,
        max_concurrency: 8,
        timeout: :infinity
      )
      |> Enum.map(fn {:ok, result} -> result end)

    posted = Enum.count(results, &match?({:ok, _document}, &1))
    rejected = Enum.count(results, &match?({:error, _error}, &1))

    # Проведено ровно столько, сколько помещается в остаток.
    assert posted == 5
    assert rejected == 3

    balance = balance(actor, warehouse.id, nomenclature.id)
    assert Decimal.compare(balance.quantity, 0) in [:gt, :eq]
    assert decimal(balance.quantity) == 0
    assert decimal(balance.cost) == 0
  end

  test "параллельные поступления суммируются без потерь", context do
    %{actor: actor, warehouse: warehouse, nomenclature: nomenclature} = context

    receipts = for _index <- 1..6, do: create_receipt(context, "5", "100")

    results =
      receipts
      |> Task.async_stream(
        fn receipt -> Posting.post(receipt, actor, Pulse.Posting.PurchasingReceipt) end,
        max_concurrency: 6,
        timeout: :infinity
      )
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.all?(results, &match?({:ok, _document}, &1))

    balance = balance(actor, warehouse.id, nomenclature.id)
    assert decimal(balance.quantity) == 30
    assert decimal(balance.cost) == 3000
  end

  defp post_receipt(context, quantity, price) do
    %{actor: actor} = context

    receipt = create_receipt(context, quantity, price)
    {:ok, posted} = Posting.post(receipt, actor, Pulse.Posting.PurchasingReceipt)
    posted
  end

  defp create_receipt(context, quantity, price) do
    %{actor: actor, counterparty: counterparty, warehouse: warehouse, nomenclature: nomenclature} =
      context

    {:ok, document} =
      Purchasing.Receipt
      |> Ash.Changeset.for_create(:create, %{
        doc_date: ~D[2026-10-20],
        counterparty_id: counterparty.id,
        warehouse_id: warehouse.id
      })
      |> Ash.Changeset.set_tenant(actor.organization_id)
      |> Ash.create(actor: actor)

    add_line(Purchasing.ReceiptLine, document, nomenclature.id, quantity, price)
    reload(Purchasing.Receipt, document.id, actor)
  end

  defp create_shipment(context, quantity, price) do
    %{actor: actor, counterparty: counterparty, warehouse: warehouse, nomenclature: nomenclature} =
      context

    {:ok, document} =
      Sales.Shipment
      |> Ash.Changeset.for_create(:create, %{
        doc_date: ~D[2026-10-20],
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

  defp balance(actor, warehouse_id, nomenclature_id) do
    context = Pulse.Posting.Context.build(%{organization_id: actor.organization_id}, actor)
    Pulse.Posting.Stock.balance(context, warehouse_id, nomenclature_id, ~D[2026-12-31])
  end

  defp decimal(value), do: Decimal.to_float(value)
end
