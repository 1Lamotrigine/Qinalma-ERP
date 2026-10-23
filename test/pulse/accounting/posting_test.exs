defmodule Pulse.Accounting.PostingTest do
  @moduledoc """
  Проведение документов: сквозной сценарий, отмена, остатки, период.

  Критерии этапа 3: «поступление → остаток → реализация» даёт
  сходящиеся цифры; «провести → отменить» возвращает регистры
  в исходное состояние; остаток не уходит в минус; проведение и
  отмена идут в одной транзакции.
  """
  use Pulse.DataCase, async: true

  import Pulse.Factory
  require Ash.Query

  alias Pulse.Accounting.Posting
  alias Pulse.Core
  alias Pulse.Ledger.StockMovement
  alias Pulse.Purchasing
  alias Pulse.Sales

  setup do
    seed_default_permissions!()
    seed_chart_of_accounts!()

    organization = create_organization(%{name: "Склад-Орг"})
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
    nomenclature = create_nomenclature(actor, %{name: "Товар-1"})

    %{
      actor: actor,
      organization: organization,
      warehouse: warehouse,
      counterparty: counterparty,
      nomenclature: nomenclature
    }
  end

  describe "сквозной сценарий" do
    test "поступление → остаток → реализация", context do
      %{actor: actor, warehouse: warehouse, nomenclature: nomenclature} = context

      receipt = post_receipt(context, quantity: "10", price: "1000")
      assert receipt.status == :posted

      assert [receipt_movement] = stock_movements(receipt)
      assert receipt_movement.record_type == :receipt
      assert decimal(receipt_movement.quantity) == 10
      assert decimal(receipt_movement.cost) == 10_000

      balance = balance(actor, warehouse.id, nomenclature.id, ~D[2026-10-20])
      assert decimal(balance.quantity) == 10
      assert decimal(balance.cost) == 10_000
      assert decimal(balance.unit_cost) == 1000

      shipment = post_shipment(context, quantity: "4", price: "1500")
      assert shipment.status == :posted

      assert [shipment_movement] = stock_movements(shipment)
      assert shipment_movement.record_type == :expense
      assert decimal(shipment_movement.quantity) == 4

      # Себестоимость расхода — по средней взвешенной: 4 × 1000.
      assert decimal(shipment_movement.cost) == 4000

      balance = balance(actor, warehouse.id, nomenclature.id, ~D[2026-10-20])
      assert decimal(balance.quantity) == 6
      assert decimal(balance.cost) == 6000
    end

    test "средняя себестоимость пересчитывается по двум поступлениям", context do
      %{actor: actor, warehouse: warehouse, nomenclature: nomenclature} = context

      post_receipt(context, quantity: "10", price: "1000")
      post_receipt(context, quantity: "10", price: "2000")

      balance = balance(actor, warehouse.id, nomenclature.id, ~D[2026-10-20])
      assert decimal(balance.quantity) == 20
      assert decimal(balance.cost) == 30_000
      assert decimal(balance.unit_cost) == 1500

      shipment = post_shipment(context, quantity: "2", price: "3000")
      assert [movement] = stock_movements(shipment)
      assert decimal(movement.cost) == 3000
    end
  end

  describe "отмена проведения" do
    test "возвращает регистры в исходное состояние", context do
      %{actor: actor, warehouse: warehouse, nomenclature: nomenclature} = context

      receipt = post_receipt(context, quantity: "10", price: "1000")
      assert [_movement] = stock_movements(receipt)

      assert {:ok, draft} = Posting.unpost(receipt, actor, Pulse.Posting.PurchasingReceipt)
      assert draft.status == :draft
      assert draft.posted_at == nil
      assert draft.posted_by == nil

      assert stock_movements(receipt) == []

      balance = balance(actor, warehouse.id, nomenclature.id, ~D[2026-10-20])
      assert decimal(balance.quantity) == 0
      assert decimal(balance.cost) == 0
    end

    test "повторное проведение после отмены даёт те же движения", context do
      %{actor: actor, warehouse: warehouse, nomenclature: nomenclature} = context

      receipt = post_receipt(context, quantity: "10", price: "1000")
      {:ok, draft} = Posting.unpost(receipt, actor, Pulse.Posting.PurchasingReceipt)

      reloaded = reload(Purchasing.Receipt, draft.id, actor)
      {:ok, posted} = Posting.post(reloaded, actor, Pulse.Posting.PurchasingReceipt)

      assert [movement] = stock_movements(posted)
      assert decimal(movement.cost) == 10_000

      balance = balance(actor, warehouse.id, nomenclature.id, ~D[2026-10-20])
      assert decimal(balance.quantity) == 10
    end
  end

  describe "остатки" do
    test "расход больше остатка отклоняется", context do
      %{actor: actor, warehouse: warehouse, nomenclature: nomenclature} = context

      post_receipt(context, quantity: "5", price: "1000")

      shipment = create_shipment(context, quantity: "6", price: "1500")

      assert {:error, message} = Posting.post(shipment, actor, Pulse.Posting.SalesShipment)
      assert message =~ "недостаточно ТМЗ"

      assert stock_movements(shipment) == []

      balance = balance(actor, warehouse.id, nomenclature.id, ~D[2026-10-20])
      assert decimal(balance.quantity) == 5
    end

    test "расход без поступления отклоняется", context do
      %{actor: actor} = context

      shipment = create_shipment(context, quantity: "1", price: "1500")

      assert {:error, _message} = Posting.post(shipment, actor, Pulse.Posting.SalesShipment)
      assert stock_movements(shipment) == []
    end
  end

  describe "жизненный цикл" do
    test "повторное проведение запрещено", context do
      %{actor: actor} = context

      receipt = post_receipt(context, quantity: "1", price: "100")

      assert {:error, message} = Posting.post(receipt, actor, Pulse.Posting.PurchasingReceipt)
      assert message =~ "уже в статусе"
    end

    test "отмена не проведённого документа запрещена", context do
      %{actor: actor} = context

      receipt = create_receipt(context, quantity: "1", price: "100")

      assert {:error, message} = Posting.unpost(receipt, actor, Pulse.Posting.PurchasingReceipt)
      assert message =~ "отменить можно только проведённый"
    end
  end

  describe "закрытый период" do
    test "проведение в закрытом периоде запрещено", context do
      %{actor: actor, organization: organization} = context

      {:ok, _result} =
        Pulse.Accounting.Periods.close_month(~D[2026-10-01], organization.id, actor)

      receipt = create_receipt(context, quantity: "1", price: "100")

      assert {:error, message} = Posting.post(receipt, actor, Pulse.Posting.PurchasingReceipt)
      assert message =~ "период"
      assert message =~ "закрыт"

      assert stock_movements(receipt) == []
    end

    test "отмена в закрытом периоде запрещена", context do
      %{actor: actor, organization: organization} = context

      receipt = post_receipt(context, quantity: "1", price: "100")

      {:ok, _result} =
        Pulse.Accounting.Periods.close_month(~D[2026-10-01], organization.id, actor)

      assert {:error, message} = Posting.unpost(receipt, actor, Pulse.Posting.PurchasingReceipt)
      assert message =~ "закрыт"

      # Движения на месте: отмена не прошла частично.
      assert [_movement] = stock_movements(receipt)
    end
  end

  describe "изоляция по организациям" do
    test "движения чужой организации недоступны", context do
      %{actor: actor} = context

      post_receipt(context, quantity: "1", price: "100")

      other = create_actor("admin")

      assert {:ok, []} = Ash.read(StockMovement, actor: other, tenant: other.organization_id)

      assert {:ok, [_movement]} =
               Ash.read(StockMovement, actor: actor, tenant: actor.organization_id)
    end
  end

  # --- построение документов ------------------------------------------------

  defp create_receipt(context, opts) do
    %{actor: actor, counterparty: counterparty, warehouse: warehouse, nomenclature: nomenclature} =
      context

    {:ok, document} =
      Purchasing.Receipt
      |> Ash.Changeset.for_create(:create, %{
        doc_date: ~D[2026-10-20],
        number: "П-001",
        counterparty_id: counterparty.id,
        warehouse_id: warehouse.id
      })
      |> Ash.Changeset.set_tenant(actor.organization_id)
      |> Ash.create(actor: actor)

    add_line(Purchasing.ReceiptLine, document, nomenclature.id, opts)

    reload(Purchasing.Receipt, document.id, actor)
  end

  defp post_receipt(context, opts) do
    %{actor: actor} = context

    document = create_receipt(context, opts)
    {:ok, posted} = Posting.post(document, actor, Pulse.Posting.PurchasingReceipt)
    posted
  end

  defp create_shipment(context, opts) do
    %{actor: actor, counterparty: counterparty, warehouse: warehouse, nomenclature: nomenclature} =
      context

    {:ok, document} =
      Sales.Shipment
      |> Ash.Changeset.for_create(:create, %{
        doc_date: ~D[2026-10-20],
        number: "Р-001",
        counterparty_id: counterparty.id,
        warehouse_id: warehouse.id
      })
      |> Ash.Changeset.set_tenant(actor.organization_id)
      |> Ash.create(actor: actor)

    add_line(Sales.ShipmentLine, document, nomenclature.id, opts)

    reload(Sales.Shipment, document.id, actor)
  end

  defp post_shipment(context, opts) do
    %{actor: actor} = context

    document = create_shipment(context, opts)
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

  # Движения ТМЗ: документы пишут ещё и в регистры расчётов, а эти
  # тесты проверяют склад.
  defp stock_movements(document) do
    document
    |> Posting.movements()
    |> Enum.filter(&match?(%StockMovement{}, &1))
  end

  defp balance(actor, warehouse_id, nomenclature_id, date) do
    context = Pulse.Posting.Context.build(%{organization_id: actor.organization_id}, actor)
    Pulse.Posting.Stock.balance(context, warehouse_id, nomenclature_id, date)
  end

  defp decimal(value), do: Decimal.to_float(value)
end
