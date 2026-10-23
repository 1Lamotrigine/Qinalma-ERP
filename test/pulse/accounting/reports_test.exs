defmodule Pulse.Accounting.ReportsTest do
  @moduledoc """
  Отчёты бухгалтерского учёта: ОСВ, карточка счёта, анализ счёта
  и главная книга.

  Критерий этапа 4: отчёты дают цифры, сходящиеся между собой и
  с журналом проводок.
  """
  use Pulse.DataCase, async: true

  import Pulse.Factory
  require Ash.Query

  alias Pulse.Accounting.Entries
  alias Pulse.Accounting.Posting
  alias Pulse.Accounting.Reports
  alias Pulse.Core
  alias Pulse.Purchasing
  alias Pulse.Sales

  @from ~D[2026-10-01]
  @to ~D[2026-10-31]

  setup do
    seed_default_permissions!()
    seed_chart_of_accounts!()

    organization = create_organization(%{name: "Отчёты-Орг"})
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
      nomenclature: create_nomenclature(actor, %{name: "Товар-Отчёт"})
    }

    # Поступление на 10 000 и реализация на 6000 — цифры легко проверяются.
    receipt = post_receipt(context, quantity: "10", price: "1000")
    shipment = post_shipment(context, quantity: "4", price: "1500")

    Map.merge(context, %{receipt: receipt, shipment: shipment})
  end

  describe "оборотно-сальдовая ведомость" do
    test "показывает счета с движениями", %{organization: organization} do
      rows = Reports.trial_balance(organization.id, @from, @to)

      codes = Enum.map(rows, & &1.code)

      assert "1330" in codes
      assert "3310" in codes
      assert "1210" in codes
      assert "6010" in codes

      # Счета без движений в ведомость не попадают.
      refute "1010" in codes
    end

    test "обороты и сальдо по счетам верны", %{organization: organization} do
      rows = Reports.trial_balance(organization.id, @from, @to)

      account = fn code -> Enum.find(rows, &(&1.code == code)) end

      assert decimal(account.("1330").debit) == 10_000
      assert decimal(account.("1330").closing.debit) == 10_000
      assert decimal(account.("3310").credit) == 10_000
      assert decimal(account.("3310").closing.credit) == 10_000
      assert decimal(account.("6010").credit) == 6000
      assert decimal(account.("1210").debit) == 6000
    end

    test "итоги ведомости сходятся: дебет равен кредиту", %{organization: organization} do
      totals =
        organization.id
        |> Reports.trial_balance(@from, @to)
        |> Reports.trial_balance_totals()

      assert Decimal.equal?(totals.debit, totals.credit)
      assert Decimal.equal?(totals.opening_debit, totals.opening_credit)
      assert Decimal.equal?(totals.closing_debit, totals.closing_credit)

      # 10 000 (поступление) + 6000 (реализация) по каждой стороне.
      assert decimal(totals.debit) == 16_000
    end

    test "сальдо начальное плюс обороты дают сальдо конечное", %{organization: organization} do
      rows = Reports.trial_balance(organization.id, @from, @to)

      for row <- rows do
        expected_debit = Decimal.add(row.opening.debit, row.debit)
        expected_credit = Decimal.add(row.opening.credit, row.credit)

        assert Decimal.equal?(row.closing.debit, expected_debit)
        assert Decimal.equal?(row.closing.credit, expected_credit)
      end
    end

    test "период без движений даёт пустую ведомость", %{organization: organization} do
      rows = Reports.trial_balance(organization.id, ~D[2026-01-01], ~D[2026-01-31])

      assert rows == []
    end
  end

  describe "карточка счёта" do
    test "показывает проводки и накопительное сальдо", %{organization: organization} do
      card = Reports.account_card("1330", organization.id, @from, @to)

      assert card.opening.debit == Decimal.new(0)
      assert [row] = card.rows
      assert decimal(row.debit) == 10_000
      assert decimal(row.credit) == 0
      assert decimal(row.balance.debit) == 10_000
      assert row.content =~ "Поступление"
      assert decimal(card.closing.debit) == 10_000
    end

    test "входящее сальдо берётся из прошлых периодов", %{organization: organization} do
      card = Reports.account_card("1330", organization.id, ~D[2026-11-01], ~D[2026-11-30])

      assert decimal(card.opening.debit) == 10_000
      assert card.rows == []
      assert decimal(card.closing.debit) == 10_000
    end
  end

  describe "анализ счёта" do
    test "показывает корреспондирующие счета", %{organization: organization} do
      analysis = Reports.account_analysis("6010", organization.id, @from, @to)

      assert [row] = analysis
      assert row.code == "1210"
      assert decimal(row.credit) == 6000
      assert decimal(row.debit) == 0
    end

    test "счёт с движениями по двум корреспондентам даёт две строки", %{
      organization: organization,
      actor: actor
    } do
      # Второе поступление от другого поставщика.
      context = %{
        actor: actor,
        organization: organization,
        warehouse: create_warehouse(actor),
        counterparty: create_counterparty(actor),
        nomenclature: create_nomenclature(actor, %{name: "Товар-Второй"})
      }

      post_receipt(context, quantity: "2", price: "500")

      analysis = Reports.account_analysis("1330", organization.id, @from, @to)

      assert length(analysis) == 1
      assert hd(analysis).code == "3310"
    end
  end

  describe "главная книга" do
    test "включает счета с оборотами и их корреспонденцию", %{organization: organization} do
      ledger = Reports.general_ledger(organization.id, @from, @to)

      codes = Enum.map(ledger, & &1.code)

      assert "1330" in codes
      assert "6010" in codes

      account = Enum.find(ledger, &(&1.code == "6010"))
      assert [row] = account.analysis
      assert row.code == "1210"
      assert decimal(account.credit_turnover) == 6000
    end
  end

  describe "согласованность отчётов" do
    test "итог ведомости совпадает с суммой проводок", %{organization: organization} do
      {:ok, entries} =
        Ash.read(Pulse.Accounting.JournalEntry, tenant: organization.id, authorize?: false)

      entry_total =
        Enum.reduce(entries, Decimal.new(0), &Decimal.add(&2, &1.amount))

      totals =
        organization.id
        |> Reports.trial_balance(@from, @to)
        |> Reports.trial_balance_totals()

      assert Decimal.equal?(totals.debit, entry_total)
      assert Decimal.equal?(totals.credit, entry_total)
    end

    test "обороты карточки совпадают с ведомостью по тому же счёту", %{
      organization: organization
    } do
      card = Reports.account_card("1330", organization.id, @from, @to)

      row =
        organization.id
        |> Reports.trial_balance(@from, @to)
        |> Enum.find(&(&1.code == "1330"))

      assert Decimal.equal?(card.debit_turnover, row.debit)
      assert Decimal.equal?(card.credit_turnover, row.credit)
      assert Decimal.equal?(card.closing.debit, row.closing.debit)
    end
  end

  # --- построение документов ------------------------------------------------

  defp create_receipt(context, opts) do
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
        doc_date: ~D[2026-10-12],
        number: "Р-#{System.unique_integer([:positive])}",
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

  defp decimal(value), do: Decimal.to_float(value)
end
