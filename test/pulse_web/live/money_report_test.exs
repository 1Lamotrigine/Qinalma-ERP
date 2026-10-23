defmodule PulseWeb.MoneyReportTest do
  @moduledoc """
  Отчёты по деньгам и расчётам: акт сверки, остатки, движение денег,
  кассовая книга.

  Критерии этапа 5: акт сверки сходится с регистром расчётов;
  кассовая книга и отчёты о движении денег строятся по регистру.
  """
  use PulseWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Pulse.Factory
  require Ash.Query

  alias Pulse.Accounting.Posting
  alias Pulse.Core
  alias Pulse.Sales
  alias Pulse.Treasury

  @reconciliation_tab "sell|Акты сверки взаиморасчетов"
  @cash_book_tab "bank|Кассовая книга"
  @balances_tab "bank|Остатки денежных средств"

  setup do
    seed_default_permissions!()
    seed_chart_of_accounts!()

    organization = create_organization(%{name: "Отчёты-Деньги"})
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
      counterparty: create_counterparty(actor, %{name: "Покупатель"}),
      supplier: create_counterparty(actor, %{name: "Складской"}),
      bank_account: create_bank_account(actor),
      cash_desk: create_cash_desk(actor),
      warehouse: create_warehouse(actor),
      nomenclature: create_nomenclature(actor, %{name: "Товар-Отчёт"})
    }

    post_receipt(context)
    Map.put(context, :conn, log_in_user(build_conn(), user))
  end

  describe "акт сверки" do
    test "строится по контрагенту и сходится с регистром", context do
      %{conn: conn, actor: actor, counterparty: counterparty} = context

      post_shipment(context, amount: "60000")
      post_bank(context, direction: :receipt, amount: "20000")

      {:ok, view, _html} = live(conn, tab(@reconciliation_tab))

      html =
        render_change(view, "report-period", %{
          "counterparty" => counterparty.id,
          "from" => "2026-10-01",
          "to" => "2026-10-31"
        })

      _ = html

      result =
        render_click(view, "generate-report", %{
          "counterparty" => counterparty.id,
          "from" => "2026-10-01",
          "to" => "2026-10-31"
        })

      assert result =~ "Оплата"
      assert has_element?(view, "#report-result table")

      # Итоги отчёта совпадают с регистром расчётов.
      totals =
        Pulse.Settlements.reconciliation_totals(
          actor.organization_id,
          counterparty.id,
          ~D[2026-10-01],
          ~D[2026-10-31]
        )

      assert Decimal.to_float(totals.closing) == 40_000
    end

    test "без контрагента отчёт просит выбрать", %{conn: conn} do
      {:ok, view, _html} = live(conn, tab(@reconciliation_tab))

      html =
        render_click(view, "generate-report", %{"from" => "2026-10-01", "to" => "2026-10-31"})

      assert html =~ "выберите контрагента"
    end
  end

  describe "кассовая книга" do
    test "показывает кассовые движения", context do
      %{conn: conn} = context

      post_cash(context, direction: :receipt, amount: "30000")
      post_cash(context, direction: :expense, amount: "10000")

      {:ok, view, _html} = live(conn, tab(@cash_book_tab))

      html =
        render_click(view, "generate-report", %{"from" => "2026-10-01", "to" => "2026-10-31"})

      assert html =~ "Поступление"
      assert html =~ "Выдача"
      assert has_element?(view, "#report-result table")
    end

    test "не включает банковские операции", context do
      %{conn: conn} = context

      post_bank(context, direction: :receipt, amount: "50000")

      {:ok, view, _html} = live(conn, tab(@cash_book_tab))

      html =
        render_click(view, "generate-report", %{"from" => "2026-10-01", "to" => "2026-10-31"})

      # В кассовой книге банковской операции быть не должно.
      assert html =~ "Нет данных за период"
    end
  end

  describe "остатки денежных средств" do
    test "показывает остаток по счёту", context do
      %{conn: conn, bank_account: account} = context

      post_bank(context, direction: :receipt, amount: "75000")

      {:ok, view, _html} = live(conn, tab(@balances_tab))

      html =
        render_click(view, "generate-report", %{"from" => "2026-10-01", "to" => "2026-10-31"})

      assert html =~ account.name
      assert html =~ "75000"
    end
  end

  defp tab(id), do: "/?tab=" <> URI.encode_www_form(id)

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

  defp post_receipt(context) do
    %{actor: actor, supplier: supplier, warehouse: warehouse, nomenclature: nomenclature} =
      context

    quantity = Decimal.new(100)
    amount = Decimal.new(100_000)

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
end
