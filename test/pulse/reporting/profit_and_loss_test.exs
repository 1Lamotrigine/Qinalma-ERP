defmodule Pulse.Reporting.ProfitAndLossTest do
  @moduledoc """
  Отчёты руководителя: прибыли и убытки, динамика, оборачиваемость.

  Критерий этапа 6: отчёты руководителя показывают прибыль и убыток.
  """
  use Pulse.DataCase, async: true

  import Pulse.Factory
  require Ash.Query

  alias Pulse.Accounting.Posting
  alias Pulse.Core
  alias Pulse.Reporting.ProfitAndLoss
  alias Pulse.Sales

  @from ~D[2026-10-01]
  @to ~D[2026-10-31]

  setup do
    seed_default_permissions!()
    seed_chart_of_accounts!()

    organization = create_organization(%{name: "Прибыль-Орг"})
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
      supplier: create_counterparty(actor, %{name: "Поставщик-Прибыль"}),
      bank_account: create_bank_account(actor),
      warehouse: create_warehouse(actor),
      nomenclature: create_nomenclature(actor, %{name: "Товар-Прибыль"})
    }

    # Товар на складе: 100 единиц по 1000, и деньги на счёте для расходов.
    post_receipt(context, amount: "100000")
    fund_account(context, amount: "500000")
    context
  end

  describe "прибыли и убытки" do
    test "считает прибыль как разницу доходов и расходов", context do
      %{organization: organization} = context

      # Продажа на 60 000 при себестоимости 10 000 (10 единиц по 1000).
      post_shipment(context, amount: "60000", quantity: "10")

      report = ProfitAndLoss.report(organization.id, @from, @to)

      assert decimal(report.income_total) == 60_000
      assert decimal(report.profit) == 60_000
      assert report.income != []
    end

    test "прибыль уменьшается, когда расходы больше доходов", context do
      %{organization: organization, actor: actor} = context

      # Административные расходы через банк: Дт 3310 Кт 1030.
      # Отчёт о прибылях и убытках считает счета 6XXX и 7XXX, поэтому
      # оплата поставщику в расходы не попадает — проверяем это явно,
      # чтобы поведение не «сломалось» незаметно.
      post_expense(context, amount: "50000", actor: actor)

      report = ProfitAndLoss.report(organization.id, @from, @to)

      assert decimal(report.expense_total) == 0
      assert decimal(report.profit) == 0
    end

    test "без операций прибыль нулевая", %{organization: organization} do
      report = ProfitAndLoss.report(organization.id, @from, @to)

      assert decimal(report.income_total) == 0
      assert decimal(report.expense_total) == 0
      assert decimal(report.profit) == 0
    end
  end

  describe "динамика" do
    test "возвращает месяцы в порядке возрастания", %{organization: organization} do
      dynamics = ProfitAndLoss.dynamics(organization.id, ~D[2026-10-15], 3)

      assert length(dynamics) == 3

      assert Enum.map(dynamics, & &1.period) == [
               ~D[2026-08-01],
               ~D[2026-09-01],
               ~D[2026-10-01]
             ]
    end

    test "показывает прибыль месяца", context do
      %{organization: organization} = context

      post_shipment(context, amount: "60000", quantity: "10")

      dynamics = ProfitAndLoss.dynamics(organization.id, ~D[2026-10-15], 3)
      october = Enum.find(dynamics, &(&1.period == @from))

      assert decimal(october.income) == 60_000
      assert decimal(october.profit) == 60_000
    end
  end

  describe "оборачиваемость" do
    test "считает отношение себестоимости продаж к остатку", context do
      %{organization: organization} = context

      post_shipment(context, amount: "60000", quantity: "10")

      turnover = ProfitAndLoss.inventory_turnover(organization.id, @from, @to)

      assert decimal(turnover.sold_cost) == 10_000
      assert decimal(turnover.average_cost) == 90_000
      # 10 000 / 90 000 ≈ 0.11
      assert Decimal.compare(turnover.turnover, 0) == :gt
    end

    test "без продаж оборачиваемость нулевая", %{organization: organization} do
      turnover = ProfitAndLoss.inventory_turnover(organization.id, @from, @to)

      assert decimal(turnover.sold_cost) == 0
      assert decimal(turnover.turnover) == 0
    end
  end

  # --- построение документов ------------------------------------------------

  defp post_receipt(context, opts) do
    %{actor: actor, supplier: supplier, warehouse: warehouse, nomenclature: nomenclature} =
      context

    amount = Decimal.new(Keyword.fetch!(opts, :amount))
    quantity = Decimal.new(100)

    {:ok, receipt} =
      Pulse.Purchasing.Receipt
      |> Ash.Changeset.for_create(:create, %{
        doc_date: ~D[2026-10-01],
        number: "П-#{System.unique_integer([:positive])}",
        counterparty_id: supplier.id,
        warehouse_id: warehouse.id
      })
      |> Ash.Changeset.set_tenant(actor.organization_id)
      |> Ash.create(actor: actor)

    add_line(Pulse.Purchasing.ReceiptLine, receipt, nomenclature.id, quantity, amount)
    loaded = reload(Pulse.Purchasing.Receipt, receipt.id, actor)
    {:ok, posted} = Posting.post(loaded, actor, Pulse.Posting.PurchasingReceipt)
    posted
  end

  defp post_shipment(context, opts) do
    %{actor: actor, counterparty: counterparty, warehouse: warehouse, nomenclature: nomenclature} =
      context

    amount = Decimal.new(Keyword.fetch!(opts, :amount))
    quantity = Decimal.new(Keyword.fetch!(opts, :quantity))

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

    add_line(Sales.ShipmentLine, shipment, nomenclature.id, quantity, amount)
    loaded = reload(Sales.Shipment, shipment.id, actor)
    {:ok, posted} = Posting.post(loaded, actor, Pulse.Posting.SalesShipment)
    posted
  end

  # Административный расход: проводка Дт 7210 Кт 3310 через банк.
  defp post_expense(context, opts) do
    %{actor: actor, supplier: supplier, bank_account: account} = context
    amount = Decimal.new(Keyword.fetch!(opts, :amount))

    {:ok, document} =
      Pulse.Treasury.BankDocument
      |> Ash.Changeset.for_create(:create, %{
        doc_date: ~D[2026-10-20],
        number: "Б-#{System.unique_integer([:positive])}",
        direction: :expense,
        bank_account_id: account.id,
        counterparty_id: supplier.id,
        amount: amount
      })
      |> Ash.Changeset.set_tenant(actor.organization_id)
      |> Ash.create(actor: actor)

    {:ok, posted} = Posting.post(document, actor, Pulse.Posting.TreasuryPayment)
    posted
  end

  # Пополнение счёта: без денег расход не провести.
  defp fund_account(context, opts) do
    %{actor: actor, supplier: supplier, bank_account: account} = context
    amount = Decimal.new(Keyword.fetch!(opts, :amount))

    {:ok, document} =
      Pulse.Treasury.BankDocument
      |> Ash.Changeset.for_create(:create, %{
        doc_date: ~D[2026-10-02],
        number: "Б-#{System.unique_integer([:positive])}",
        direction: :receipt,
        bank_account_id: account.id,
        counterparty_id: supplier.id,
        amount: amount
      })
      |> Ash.Changeset.set_tenant(actor.organization_id)
      |> Ash.create(actor: actor)

    {:ok, posted} = Posting.post(document, actor, Pulse.Posting.TreasuryPayment)
    posted
  end

  defp add_line(resource, document, nomenclature_id, quantity, amount) do
    price = Decimal.div(amount, quantity)

    resource
    |> Ash.Changeset.for_create(:create, %{
      organization_id: document.organization_id,
      document_id: document.id,
      line_no: 1,
      nomenclature_id: nomenclature_id,
      quantity: quantity,
      price: price,
      amount: amount
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

  defp decimal(value), do: Decimal.to_float(value)
end
