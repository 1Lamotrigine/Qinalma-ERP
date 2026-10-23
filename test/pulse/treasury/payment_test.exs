defmodule Pulse.Treasury.PaymentTest do
  @moduledoc """
  Деньги и взаиморасчёты: проведение оплат, остатки, зачёт аванса.

  Критерии этапа 5: банковские и кассовые документы влияют на остатки
  денег; зачёт аванса срабатывает автоматически при оплате и реализации;
  акт сверки сходится с регистром расчётов.
  """
  use Pulse.DataCase, async: true

  import Pulse.Factory
  require Ash.Query

  alias Pulse.Accounting.Posting
  alias Pulse.Core
  alias Pulse.Sales
  alias Pulse.Settlements
  alias Pulse.Treasury

  setup do
    seed_default_permissions!()
    seed_chart_of_accounts!()

    organization = create_organization(%{name: "Деньги-Орг"})
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
      supplier: create_counterparty(actor, %{name: "Поставщик"}),
      stock_supplier: create_counterparty(actor, %{name: "Складской поставщик"}),
      bank_account: create_bank_account(actor),
      cash_desk: create_cash_desk(actor),
      warehouse: create_warehouse(actor),
      nomenclature: create_nomenclature(actor, %{name: "Товар-Деньги"})
    }

    # Товар на складе: без остатка реализацию не провести. Поступление
    # идёт от отдельного поставщика, чтобы не путать расчёты в тестах.
    post_receipt(context, counterparty: context.stock_supplier)

    context
  end

  describe "банковские документы" do
    test "поступление увеличивает остаток счёта", context do
      %{bank_account: account} = context

      document = post_bank(context, direction: :receipt, amount: "100000")

      assert document.status == :posted
      assert decimal(cash_balance(context, :bank, account.id)) == 100_000
    end

    test "списание уменьшает остаток счёта", context do
      %{bank_account: account} = context

      post_bank(context, direction: :receipt, amount: "100000")
      post_bank(context, direction: :expense, amount: "30000")

      assert decimal(cash_balance(context, :bank, account.id)) == 70_000
    end

    test "списание больше остатка отклоняется", context do
      %{actor: actor, bank_account: account} = context

      post_bank(context, direction: :receipt, amount: "10000")
      document = create_bank(context, direction: :expense, amount: "50000")

      assert {:error, message} = Posting.post(document, actor, Pulse.Posting.TreasuryPayment)
      assert message =~ "недостаточно денежных средств"

      assert decimal(cash_balance(context, :bank, account.id)) == 10_000
    end
  end

  describe "кассовые документы" do
    test "ПКО и РКО меняют остаток кассы", context do
      %{cash_desk: cash_desk} = context

      post_cash(context, direction: :receipt, amount: "50000")
      post_cash(context, direction: :expense, amount: "20000")

      assert decimal(cash_balance(context, :cash, cash_desk.id)) == 30_000
    end

    test "проведение создаёт движение денег и проводку", context do
      %{organization: organization} = context

      document = post_cash(context, direction: :receipt, amount: "50000")

      # Деньги и взаиморасчёты пишутся в разные регистры.
      movements = Posting.movements(document)

      assert Enum.any?(movements, &match?(%Pulse.Ledger.CashMovement{}, &1))
      assert Enum.any?(movements, &match?(%Pulse.Ledger.SettlementMovement{}, &1))

      {:ok, entries} =
        Ash.read(Pulse.Accounting.JournalEntry, tenant: organization.id, authorize?: false)

      # Отфильтровываем проводку поступления из setup.
      entry = Enum.find(entries, &(&1.document_id == document.id))

      assert entry.debit_account_code == "1010"
      assert Decimal.equal?(entry.amount, Decimal.new(50_000))
    end
  end

  describe "отмена проведения" do
    test "возвращает остаток и удаляет движения", context do
      %{actor: actor, bank_account: account} = context

      document = post_bank(context, direction: :receipt, amount: "100000")
      assert decimal(cash_balance(context, :bank, account.id)) == 100_000

      {:ok, draft} = Posting.unpost(document, actor, Pulse.Posting.TreasuryPayment)

      assert draft.status == :draft
      assert decimal(cash_balance(context, :bank, account.id)) == 0
      assert Posting.movements(document) == []
    end
  end

  describe "взаиморасчёты" do
    test "реализация создаёт долг покупателя", context do
      %{organization: organization, counterparty: counterparty} = context

      post_shipment(context, amount: "60000")

      # В setup есть поступление от другого поставщика — берём нашего.
      debt = Settlements.debt(organization.id, counterparty.id, nil, ~D[2026-10-31])
      assert decimal(debt.debit) == 60_000
      assert decimal(debt.balance) == 60_000
    end

    test "оплата закрывает долг покупателя", context do
      %{organization: organization, counterparty: counterparty} = context

      post_shipment(context, amount: "60000")
      post_bank(context, direction: :receipt, amount: "60000")

      debt = Settlements.debt(organization.id, counterparty.id, nil, ~D[2026-10-31])
      assert decimal(debt.balance) == 0
    end

    test "частичная оплата оставляет остаток долга", context do
      %{organization: organization, counterparty: counterparty} = context

      post_shipment(context, amount: "60000")
      post_bank(context, direction: :receipt, amount: "25000")

      debt = Settlements.debt(organization.id, counterparty.id, nil, ~D[2026-10-31])
      assert decimal(debt.debit) == 35_000
    end
  end

  describe "зачёт аванса" do
    test "аванс от покупателя зачитывается при реализации", context do
      %{organization: organization, counterparty: counterparty} = context

      # Сначала оплата, потом отгрузка — на момент отгрузки есть аванс.
      post_bank(context, direction: :receipt, amount: "60000")
      post_shipment(context, amount: "60000")

      debt = Settlements.debt(organization.id, counterparty.id, nil, ~D[2026-10-31])

      # Аванс и долг гасят друг друга: сальдо нулевое.
      assert decimal(debt.balance) == 0
      assert decimal(debt.overdue) == 0
    end

    test "аванс поставщику закрывается при поступлении", context do
      %{organization: organization, supplier: supplier} = context

      # Пополняем счёт, затем оплачиваем поставщику вперёд — аванс выданный.
      post_bank(context, direction: :receipt, amount: "100000")
      post_bank(context, direction: :expense, amount: "40000", counterparty: supplier)

      debt = Settlements.debt(organization.id, supplier.id, nil, ~D[2026-10-31])
      assert decimal(debt.credit) == -40_000
      assert decimal(debt.advance) == 40_000

      # Поступление от того же поставщика закрывает аванс.
      post_receipt_for(context, amount: "40000", counterparty: supplier)

      debt = Settlements.debt(organization.id, supplier.id, nil, ~D[2026-10-31])
      assert decimal(debt.credit) == 0
      assert decimal(debt.advance) == 0
    end
  end

  describe "акт сверки" do
    test "сходится с регистром расчётов", context do
      %{organization: organization, counterparty: counterparty} = context

      post_shipment(context, amount: "60000")
      post_bank(context, direction: :receipt, amount: "20000")

      totals =
        Settlements.reconciliation_totals(
          organization.id,
          counterparty.id,
          ~D[2026-10-01],
          ~D[2026-10-31]
        )

      assert decimal(totals.opening) == 0
      assert decimal(totals.closing) == 40_000

      movements =
        Settlements.reconciliation(
          organization.id,
          counterparty.id,
          ~D[2026-10-01],
          ~D[2026-10-31]
        )

      assert movements != []

      computed =
        Enum.reduce(movements, Decimal.new(0), fn movement, acc ->
          sign = if movement.direction == :payment, do: -1, else: 1
          Decimal.add(acc, Decimal.mult(sign, movement.amount))
        end)

      assert Decimal.equal?(computed, totals.closing)
    end
  end

  # --- построение документов ------------------------------------------------

  defp create_bank(context, opts) do
    %{actor: actor, bank_account: account, counterparty: default_counterparty} = context
    counterparty = Keyword.get(opts, :counterparty, default_counterparty)

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

    document
  end

  defp post_bank(context, opts) do
    %{actor: actor} = context

    document = create_bank(context, opts)
    {:ok, posted} = Posting.post(document, actor, Pulse.Posting.TreasuryPayment)
    posted
  end

  defp post_cash(context, opts) do
    %{actor: actor, cash_desk: cash_desk, counterparty: counterparty} = context

    {:ok, document} =
      Treasury.CashDocument
      |> Ash.Changeset.for_create(:create, %{
        doc_date: ~D[2026-10-20],
        number: "К-#{System.unique_integer([:positive])}",
        direction: Keyword.fetch!(opts, :direction),
        cash_desk_id: cash_desk.id,
        counterparty_id: counterparty.id,
        amount: Decimal.new(Keyword.fetch!(opts, :amount))
      })
      |> Ash.Changeset.set_tenant(actor.organization_id)
      |> Ash.create(actor: actor)

    {:ok, posted} = Posting.post(document, actor, Pulse.Posting.TreasuryPayment)
    posted
  end

  defp post_receipt(context, opts) do
    post_receipt_for(context, Keyword.merge([amount: "100000"], opts))
  end

  # Поступление от контрагента из контекста на заданную сумму —
  # вторая сторона взаиморасчётов для проверки зачёта аванса.
  defp post_receipt_for(context, opts) do
    %{actor: actor, warehouse: warehouse, nomenclature: nomenclature} = context
    counterparty = Keyword.get(opts, :counterparty, context.supplier)

    amount = Decimal.new(Keyword.fetch!(opts, :amount))
    quantity = Decimal.new(100)

    {:ok, receipt} =
      Pulse.Purchasing.Receipt
      |> Ash.Changeset.for_create(:create, %{
        doc_date: ~D[2026-10-10],
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

    quantity = Decimal.new(10)

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

  defp cash_balance(context, kind, account_id) do
    %{organization: organization} = context
    Settlements.cash_balance(organization.id, kind, account_id, ~D[2026-10-31])
  end

  defp decimal(value), do: Decimal.to_float(value)
end
