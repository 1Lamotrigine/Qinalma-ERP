defmodule Pulse.Accounting.PostingPropertyTest do
  @moduledoc """
  Свойства проведения (StreamData, раздел 10 ТЗ).

  Проверяются инварианты, которые обязаны держаться на любых данных:
  «провести → отменить» возвращает регистры в исходное состояние и
  остатки не уходят в минус при допустимом порядке документов.
  """
  use Pulse.DataCase, async: true
  use ExUnitProperties

  import Pulse.Factory
  require Ash.Query

  alias Pulse.Accounting.Posting
  alias Pulse.Core
  alias Pulse.Purchasing
  alias Pulse.Sales

  setup do
    seed_default_permissions!()
    seed_chart_of_accounts!()

    organization = create_organization(%{name: "Свойства-Орг"})
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
      nomenclature: create_nomenclature(actor, %{name: "Товар-Свойство"})
    }
  end

  property "провести → отменить возвращает остаток в исходное состояние", context do
    check all(
            quantity <- integer(1..50),
            price <- integer(1..10_000),
            max_runs: 15
          ) do
      %{actor: actor, warehouse: warehouse, nomenclature: nomenclature} = context

      before_balance = balance(actor, warehouse.id, nomenclature.id)

      receipt = create_receipt(context, quantity, price)
      {:ok, posted} = Posting.post(receipt, actor, Pulse.Posting.PurchasingReceipt)

      posted_balance = balance(actor, warehouse.id, nomenclature.id)
      assert decimal(posted_balance.quantity) == decimal(before_balance.quantity) + quantity
      assert decimal(posted_balance.cost) == decimal(before_balance.cost) + quantity * price

      {:ok, _draft} = Posting.unpost(posted, actor, Pulse.Posting.PurchasingReceipt)

      after_balance = balance(actor, warehouse.id, nomenclature.id)
      assert decimal(after_balance.quantity) == decimal(before_balance.quantity)
      assert decimal(after_balance.cost) == decimal(before_balance.cost)
      assert stock_movements(posted) == []
    end
  end

  property "расход не уходит в минус: остаток всегда неотрицателен", context do
    check all(
            receipts <- list_of({integer(1..20), integer(1..1000)}, min_length: 1, max_length: 3),
            expenses <- list_of(integer(1..30), min_length: 1, max_length: 4),
            max_runs: 15
          ) do
      %{actor: actor, warehouse: warehouse, nomenclature: nomenclature} = context

      # Каждая итерация работает со своим складом: свойство проверяет
      # арифметику остатка, а не накопленное состояние прошлых прогонов.
      warehouse = create_warehouse(actor)
      context = %{context | warehouse: warehouse}

      total_received =
        Enum.reduce(receipts, 0, fn {quantity, price}, acc ->
          receipt = create_receipt(context, quantity, price)
          {:ok, posted} = Posting.post(receipt, actor, Pulse.Posting.PurchasingReceipt)
          assert posted.status == :posted
          acc + quantity
        end)

      Enum.reduce(expenses, total_received, fn quantity, available ->
        shipment = create_shipment(context, quantity, 500)
        result = Posting.post(shipment, actor, Pulse.Posting.SalesShipment)

        if quantity <= available do
          assert {:ok, posted} = result
          assert posted.status == :posted
          available - quantity
        else
          assert {:error, _message} = result
          available
        end
      end)

      balance = balance(actor, warehouse.id, nomenclature.id)
      assert Decimal.compare(balance.quantity, 0) in [:gt, :eq]
      assert Decimal.compare(balance.cost, 0) in [:gt, :eq]
    end
  end

  property "стоимость остатка равна сумме стоимостей движений", context do
    check all(
            receipts <- list_of({integer(1..10), integer(1..500)}, min_length: 1, max_length: 3),
            expense <- integer(1..5),
            max_runs: 10
          ) do
      %{actor: actor, warehouse: warehouse, nomenclature: nomenclature} = context

      Enum.each(receipts, fn {quantity, price} ->
        {:ok, _posted} =
          context
          |> create_receipt(quantity, price)
          |> Posting.post(actor, Pulse.Posting.PurchasingReceipt)
      end)

      balance_before = balance(actor, warehouse.id, nomenclature.id)

      if Decimal.compare(balance_before.quantity, expense) != :lt do
        {:ok, shipment} =
          context
          |> create_shipment(expense, 700)
          |> Posting.post(actor, Pulse.Posting.SalesShipment)

        assert [movement] = stock_movements(shipment)

        expected_cost = Decimal.mult(balance_before.unit_cost, Decimal.new(expense))
        assert decimal(movement.cost) == decimal(expected_cost)
      end
    end
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

  # Движения ТМЗ: документы пишут ещё и в регистры расчётов.
  defp stock_movements(document) do
    document
    |> Posting.movements()
    |> Enum.filter(&match?(%Pulse.Ledger.StockMovement{}, &1))
  end

  defp balance(actor, warehouse_id, nomenclature_id) do
    context = Pulse.Posting.Context.build(%{organization_id: actor.organization_id}, actor)
    Pulse.Posting.Stock.balance(context, warehouse_id, nomenclature_id, ~D[2026-12-31])
  end

  defp decimal(value), do: Decimal.to_float(value)
end
