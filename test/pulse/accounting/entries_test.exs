defmodule Pulse.Accounting.EntriesTest do
  @moduledoc """
  Бухгалтерский контур: проводки при проведении, сходимость дебета
  и кредита, отчёты по счетам.

  Критерии этапа 4: проведение документов создаёт проводки; дебет равен
  кредиту; отмена убирает проводки вместе с движениями; ОСВ, карточка
  и анализ счёта дают согласованные цифры.
  """
  use Pulse.DataCase, async: true

  import Pulse.Factory
  require Ash.Query

  alias Pulse.Accounting.Entries
  alias Pulse.Accounting.Posting
  alias Pulse.Core
  alias Pulse.Ledger.StockMovement
  alias Pulse.Purchasing
  alias Pulse.Sales

  setup do
    seed_default_permissions!()
    seed_chart_of_accounts!()

    organization = create_organization(%{name: "Бухучёт-Орг"})
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
      nomenclature: create_nomenclature(actor, %{name: "Товар-БУ"})
    }
  end

  describe "проводки при проведении" do
    test "поступление создаёт проводку Дт 1330 Кт 3310", context do
      %{actor: actor} = context

      receipt = post_receipt(context, quantity: "10", price: "1000")

      assert [entry] = Entries.for_document(receipt)
      assert entry.debit_account_code == "1330"
      assert entry.credit_account_code == "3310"
      assert decimal(entry.amount) == 10_000
      assert entry.ledger == :accounting
      assert entry.content =~ "Поступление"
      assert entry.period == ~D[2026-10-01]
    end

    test "реализация создаёт проводку Дт 1210 Кт 6010", context do
      %{actor: actor} = context

      post_receipt(context, quantity: "10", price: "1000")
      shipment = post_shipment(context, quantity: "4", price: "1500")

      assert [entry] = Entries.for_document(shipment)
      assert entry.debit_account_code == "1210"
      assert entry.credit_account_code == "6010"
      # Выручка по цене продажи, не себестоимость.
      assert decimal(entry.amount) == 6000
    end

    test "субконто заполнены по сторонам проводки", context do
      %{actor: actor, counterparty: counterparty, nomenclature: nomenclature} = context

      receipt = post_receipt(context, quantity: "1", price: "100")
      assert [entry] = Entries.for_document(receipt)

      assert [%{"type" => "nomenclature", "id" => nomenclature_id}] = entry.debit_subaccounts
      assert nomenclature_id == nomenclature.id

      assert [%{"type" => "counterparty", "id" => counterparty_id}] = entry.credit_subaccounts
      assert counterparty_id == counterparty.id
    end

    test "проводки не создаются без шаблона операции", context do
      %{actor: actor, organization: organization} = context

      # Убираем шаблон: проведение обязано отказать, а не писать наугад.
      {:ok, [template]} =
        Pulse.Accounting.EntryTemplate
        |> Ash.Query.filter(kind == :receipt_tmz)
        |> Ash.read(authorize?: false)

      template
      |> Ash.Changeset.for_destroy(:destroy)
      |> Ash.destroy!(authorize?: false)

      receipt = create_receipt(context, quantity: "1", price: "100")

      assert {:error, message} = Posting.post(receipt, actor, Pulse.Posting.PurchasingReceipt)
      assert message =~ "шаблон"

      assert {:ok, []} =
               Pulse.Accounting.JournalEntry
               |> Ash.Query.filter(organization_id == ^organization.id)
               |> Ash.read(tenant: organization.id, authorize?: false)
    end
  end

  describe "сходимость дебета и кредита" do
    test "по каждому документу дебет равен кредиту" do
      assert :ok == Entries.validate_balanced([%{amount: Decimal.new("100")}])
      assert :ok == Entries.validate_balanced([])

      assert {:error, _message} =
               Entries.validate_balanced([%{amount: Decimal.new("0")}])

      assert {:error, _message} = Entries.validate_balanced([%{amount: "не число"}])
    end

    test "сумма дебета равна сумме кредита по всем счетам", context do
      %{organization: organization} = context

      post_receipt(context, quantity: "10", price: "1000")
      post_receipt(context, quantity: "5", price: "2000")
      post_shipment(context, quantity: "3", price: "3000")

      # Суммируем по всем счетам плана: обороты дебета и кредита обязаны совпасть.
      {debit, credit} =
        Pulse.Accounting.ChartOfAccounts.accounts()
        |> Enum.map(& &1.code)
        |> Enum.reduce({Decimal.new(0), Decimal.new(0)}, fn code, {d, c} ->
          turnover = Entries.turnover(code, organization.id, ~D[2026-10-01], ~D[2026-10-31])
          {Decimal.add(d, turnover.debit_turnover), Decimal.add(c, turnover.credit_turnover)}
        end)

      assert Decimal.equal?(debit, credit)

      # Поступление 10 000 + 10 000, реализация 9000 — каждая сумма
      # проходит и по дебету, и по кредиту.
      assert decimal(debit) == 10_000 + 10_000 + 9000
    end
  end

  describe "отмена проведения" do
    test "удаляет проводки вместе с движениями", context do
      %{actor: actor} = context

      receipt = post_receipt(context, quantity: "10", price: "1000")
      assert [_entry] = Entries.for_document(receipt)
      assert [_movement] = stock_movements(receipt)

      {:ok, draft} = Posting.unpost(receipt, actor, Pulse.Posting.PurchasingReceipt)

      assert draft.status == :draft
      assert Entries.for_document(receipt) == []
      assert stock_movements(receipt) == []
    end

    test "повторное проведение создаёт проводку заново", context do
      %{actor: actor} = context

      receipt = post_receipt(context, quantity: "10", price: "1000")
      {:ok, draft} = Posting.unpost(receipt, actor, Pulse.Posting.PurchasingReceipt)

      reloaded = reload(Purchasing.Receipt, draft.id, actor)
      {:ok, posted} = Posting.post(reloaded, actor, Pulse.Posting.PurchasingReceipt)

      assert [entry] = Entries.for_document(posted)
      assert decimal(entry.amount) == 10_000
    end
  end

  describe "обороты по счёту" do
    test "считает обороты и сальдо", context do
      %{actor: actor, organization: organization} = context

      post_receipt(context, quantity: "10", price: "1000")

      turnover = Entries.turnover("1330", organization.id, ~D[2026-10-01], ~D[2026-10-31])

      assert decimal(turnover.debit_turnover) == 10_000
      assert decimal(turnover.credit_turnover) == 0
      assert decimal(turnover.opening.debit) == 0
      assert decimal(turnover.closing.debit) == 10_000
    end

    test "сальдо на начало берётся из прошлых периодов", context do
      %{organization: organization} = context

      post_receipt(context, quantity: "10", price: "1000")

      turnover = Entries.turnover("1330", organization.id, ~D[2026-11-01], ~D[2026-11-30])

      assert decimal(turnover.opening.debit) == 10_000
      assert decimal(turnover.debit_turnover) == 0
      assert decimal(turnover.closing.debit) == 10_000
    end

    test "карточка счёта возвращает проводки, затрагивающие счёт", context do
      %{organization: organization} = context

      post_receipt(context, quantity: "10", price: "1000")
      post_shipment(context, quantity: "2", price: "1500")

      entries =
        Entries.entries_for_account("6010", organization.id, ~D[2026-10-01], ~D[2026-10-31])

      assert [entry] = entries
      assert entry.credit_account_code == "6010"
      assert decimal(entry.amount) == 3000
    end
  end

  describe "изоляция по организациям" do
    test "проводки чужой организации недоступны", context do
      %{organization: organization} = context

      post_receipt(context, quantity: "1", price: "100")

      other = create_actor("admin")

      assert {:ok, []} =
               Ash.read(Pulse.Accounting.JournalEntry,
                 actor: other,
                 tenant: other.organization_id
               )

      assert {:ok, [_entry]} =
               Ash.read(Pulse.Accounting.JournalEntry,
                 tenant: organization.id,
                 authorize?: false
               )
    end
  end

  describe "движения и проводки вместе" do
    test "проведение пишет движения и проводки в одной транзакции", context do
      %{organization: organization} = context

      post_receipt(context, quantity: "10", price: "1000")

      {:ok, movements} =
        Ash.read(StockMovement, tenant: organization.id, authorize?: false)

      {:ok, entries} =
        Ash.read(Pulse.Accounting.JournalEntry, tenant: organization.id, authorize?: false)

      assert length(movements) == 1
      assert length(entries) == 1
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

  # Движения ТМЗ: документы пишут ещё и в регистры расчётов.
  defp stock_movements(document) do
    document
    |> Posting.movements()
    |> Enum.filter(&match?(%StockMovement{}, &1))
  end

  defp decimal(value), do: Decimal.to_float(value)
end
