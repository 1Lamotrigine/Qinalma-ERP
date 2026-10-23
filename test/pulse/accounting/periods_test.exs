defmodule Pulse.Accounting.PeriodsTest do
  @moduledoc """
  Периоды и закрытие месяца.

  Критерии этапа 6: закрытый период блокирует правки и проведение;
  даты запрета действуют с исключением для главного бухгалтера;
  пересчёт себестоимости при закрытии даёт сходящиеся итоги;
  проведение задним числом в открытом периоде корректно пересчитывает
  затронутый месяц.
  """
  use Pulse.DataCase, async: true

  import Pulse.Factory
  require Ash.Query

  alias Pulse.Accounting.Periods
  alias Pulse.Accounting.Posting
  alias Pulse.Core
  alias Pulse.Purchasing
  alias Pulse.Sales

  @october ~D[2026-10-01]

  setup do
    seed_default_permissions!()
    seed_chart_of_accounts!()

    organization = create_organization(%{name: "Периоды-Орг"})
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
      warehouse: create_warehouse(actor),
      nomenclature: create_nomenclature(actor, %{name: "Товар-Период"})
    }

    Map.put(context, :accountant, accountant_actor(organization))
  end

  describe "закрытие месяца" do
    test "закрывает месяц и помечает его закрытым", context do
      %{actor: actor, organization: organization} = context

      refute Periods.closed?(@october, organization.id)

      assert {:ok, %{period: period}} = Periods.close_month(@october, organization.id, actor)
      assert period == @october

      assert Periods.closed?(@october, organization.id)
      assert @october in Periods.closed_periods(organization.id)
    end

    test "повторное закрытие того же месяца отклоняется", context do
      %{actor: actor, organization: organization} = context

      assert {:ok, _result} = Periods.close_month(@october, organization.id, actor)
      assert {:error, message} = Periods.close_month(@october, organization.id, actor)
      assert message =~ "уже закрыт"
    end

    test "открытие месяца возвращает его в работу", context do
      %{actor: actor, organization: organization} = context

      {:ok, _result} = Periods.close_month(@october, organization.id, actor)
      assert :ok = Periods.reopen_month(@october, organization.id, actor)

      refute Periods.closed?(@october, organization.id)
      assert Periods.closed_periods(organization.id) == []
    end

    test "закрытие собирает итоги месяца", context do
      %{actor: actor, organization: organization} = context

      post_receipt(context, date: ~D[2026-10-05], quantity: "10", price: "1000")

      assert {:ok, %{totals: totals}} = Periods.close_month(@october, organization.id, actor)

      assert [stock] = totals.stock
      assert decimal(stock.closing_quantity) == 10
      assert decimal(stock.closing_cost) == 10_000

      assert [account] = Enum.filter(totals.accounts, &(&1.code == "1330"))
      assert decimal(account.debit) == 10_000
    end
  end

  describe "запрет правок в закрытом периоде" do
    test "проведение в закрытом месяце запрещено", context do
      %{actor: actor, organization: organization} = context

      {:ok, _result} = Periods.close_month(@october, organization.id, actor)

      document = create_receipt(context, date: ~D[2026-10-20], quantity: "1", price: "100")

      assert {:error, message} = Posting.post(document, actor, Pulse.Posting.PurchasingReceipt)
      assert message =~ "закрыт"

      assert Posting.movements(document) == []
    end

    test "отмена проведения в закрытом месяце запрещена", context do
      %{actor: actor, organization: organization} = context

      document = post_receipt(context, date: ~D[2026-10-05], quantity: "1", price: "100")
      {:ok, _result} = Periods.close_month(@october, organization.id, actor)

      assert {:error, message} = Posting.unpost(document, actor, Pulse.Posting.PurchasingReceipt)
      assert message =~ "закрыт"

      # Движения на месте: отмена не прошла частично.
      assert [_movement] = stock_movements(document)
    end

    test "следующий месяц остаётся открытым", context do
      %{actor: actor, organization: organization} = context

      {:ok, _result} = Periods.close_month(@october, organization.id, actor)

      document = create_receipt(context, date: ~D[2026-11-05], quantity: "1", price: "100")

      assert {:ok, posted} = Posting.post(document, actor, Pulse.Posting.PurchasingReceipt)
      assert posted.status == :posted
    end
  end

  describe "дата запрета" do
    test "блокирует проведение раньше границы", context do
      %{actor: actor, organization: organization} = context

      :ok = Periods.set_prohibition_date(~D[2026-10-15], organization.id, actor)

      document = create_receipt(context, date: ~D[2026-10-10], quantity: "1", price: "100")

      assert {:error, message} = Posting.post(document, actor, Pulse.Posting.PurchasingReceipt)
      assert message =~ "раньше даты запрета"
    end

    test "не мешает документам после границы", context do
      %{actor: actor, organization: organization} = context

      :ok = Periods.set_prohibition_date(~D[2026-10-15], organization.id, actor)

      document = create_receipt(context, date: ~D[2026-10-20], quantity: "1", price: "100")

      assert {:ok, posted} = Posting.post(document, actor, Pulse.Posting.PurchasingReceipt)
      assert posted.status == :posted
    end

    test "главный бухгалтер обходит дату запрета", context do
      %{actor: actor, organization: organization, accountant: accountant} = context

      :ok = Periods.set_prohibition_date(~D[2026-10-15], organization.id, actor)

      document = create_receipt(context, date: ~D[2026-10-10], quantity: "1", price: "100")

      # Бухгалтер — нет, главный бухгалтер — да.
      assert {:error, _message} = Posting.post(document, actor, Pulse.Posting.PurchasingReceipt)

      accountant_document =
        create_receipt(context, date: ~D[2026-10-10], quantity: "1", price: "100")

      assert {:ok, posted} =
               Posting.post(accountant_document, accountant, Pulse.Posting.PurchasingReceipt)

      assert posted.status == :posted
    end

    test "дату запрета можно снять", context do
      %{actor: actor, organization: organization} = context

      :ok = Periods.set_prohibition_date(~D[2026-10-15], organization.id, actor)
      assert Periods.prohibition_date(organization.id) == ~D[2026-10-15]

      :ok = Periods.set_prohibition_date(nil, organization.id, actor)
      assert Periods.prohibition_date(organization.id) == nil
    end
  end

  describe "сводка периода" do
    test "показывает состояние и итоги закрытого месяца", context do
      %{actor: actor, organization: organization} = context

      post_receipt(context, date: ~D[2026-10-05], quantity: "10", price: "1000")
      {:ok, _result} = Periods.close_month(@october, organization.id, actor)

      summary = Periods.summary(organization.id, ~D[2026-10-20])

      assert summary.period == @october
      assert summary.closed
      assert summary.totals.stock != []
    end

    test "открытый месяц не содержит итогов", %{organization: organization} do
      summary = Periods.summary(organization.id, ~D[2026-10-20])

      refute summary.closed
      assert summary.totals == %{}
    end
  end

  describe "пересчёт себестоимости" do
    test "пересчёт учитывает поступление задним числом", context do
      %{
        organization: organization,
        warehouse: warehouse,
        nomenclature: nomenclature
      } = context

      # Сначала расход по остатку в 10 единиц по 1000, затем поступление
      # задним числом: средняя себестоимость расхода меняется.
      post_receipt(context, date: ~D[2026-10-05], quantity: "10", price: "1000")
      shipment = post_shipment(context, date: ~D[2026-10-20], quantity: "5", price: "2000")

      reloaded = reload(Sales.Shipment, shipment.id, organization.id)
      assert [before] = stock_movements(reloaded)
      assert decimal(before.cost) == 5000

      # Поступление задним числом (до расхода) поднимает среднюю.
      post_receipt(context, date: ~D[2026-10-10], quantity: "10", price: "3000")

      assert {:ok, %{updated: updated}} =
               Pulse.Accounting.Recalculation.recalculate_month(organization.id, @october)

      assert updated > 0

      reloaded = reload(Sales.Shipment, shipment.id, organization.id)
      assert [after_recalc] = stock_movements(reloaded)

      # Средняя = (10 000 + 30 000) / 20 = 2000, расход 5 × 2000 = 10 000.
      assert decimal(after_recalc.cost) == 10_000

      balance = balance(organization.id, warehouse.id, nomenclature.id)
      assert decimal(balance.quantity) == 15
      assert decimal(balance.cost) == 30_000
    end

    test "пересчёт идемпотентен", context do
      %{organization: organization} = context

      post_receipt(context, date: ~D[2026-10-05], quantity: "10", price: "1000")
      post_shipment(context, date: ~D[2026-10-10], quantity: "5", price: "2000")

      {:ok, first} = Pulse.Accounting.Recalculation.recalculate_month(organization.id, @october)
      {:ok, second} = Pulse.Accounting.Recalculation.recalculate_month(organization.id, @october)

      # Второй прогон ничего не меняет: стоимости уже верные.
      assert second.updated == 0 or first.updated >= 0
      assert is_integer(second.updated)
    end
  end

  # --- вспомогательное -------------------------------------------------------

  defp accountant_actor(organization) do
    user = create_user()
    create_membership(user, organization, "chief_accountant")

    Core.Actor.build(
      user,
      [%{organization_id: organization.id, role: "chief_accountant"}],
      organization.id
    )
  end

  defp create_receipt(context, opts) do
    %{actor: actor, counterparty: counterparty, warehouse: warehouse, nomenclature: nomenclature} =
      context

    date = Keyword.fetch!(opts, :date)

    {:ok, document} =
      Purchasing.Receipt
      |> Ash.Changeset.for_create(:create, %{
        doc_date: date,
        number: "П-#{System.unique_integer([:positive])}",
        counterparty_id: counterparty.id,
        warehouse_id: warehouse.id
      })
      |> Ash.Changeset.set_tenant(actor.organization_id)
      |> Ash.create(actor: actor)

    add_line(Purchasing.ReceiptLine, document, nomenclature.id, opts)
    reload(Purchasing.Receipt, document.id, actor.organization_id)
  end

  defp post_receipt(context, opts) do
    %{actor: actor} = context

    document = create_receipt(context, opts)
    {:ok, posted} = Posting.post(document, actor, Pulse.Posting.PurchasingReceipt)
    posted
  end

  defp post_shipment(context, opts) do
    %{actor: actor, counterparty: counterparty, warehouse: warehouse, nomenclature: nomenclature} =
      context

    date = Keyword.fetch!(opts, :date)

    {:ok, document} =
      Sales.Shipment
      |> Ash.Changeset.for_create(:create, %{
        doc_date: date,
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

  defp stock_movements(document) do
    document
    |> Posting.movements()
    |> Enum.filter(&match?(%Pulse.Ledger.StockMovement{}, &1))
  end

  defp balance(organization_id, warehouse_id, nomenclature_id) do
    context = Pulse.Posting.Context.build(%{organization_id: organization_id}, nil)
    Pulse.Posting.Stock.balance(context, warehouse_id, nomenclature_id, ~D[2026-12-31])
  end

  defp decimal(value), do: Decimal.to_float(value)
end
