defmodule Pulse.Payroll.AccrualsTest do
  @moduledoc """
  Зарплата и кадровые документы (этап 8).

  Критерии этапа: начисление считается по параметрам закона; кадровые
  документы проводятся и влияют на расчёт; ведомости на выплату связаны
  с банком и кассой; ИИН шифруется в базе.
  """
  use Pulse.DataCase, async: true

  import Pulse.Factory
  require Ash.Query

  alias Pulse.Accounting.Posting
  alias Pulse.Core
  alias Pulse.HR
  alias Pulse.HR.Person
  alias Pulse.Payroll
  alias Pulse.Payroll.Accruals

  setup do
    seed_default_permissions!()
    seed_chart_of_accounts!()
    seed_statutory_rates!()

    organization = create_organization(%{name: "Зарплата-Орг"})
    user = create_user()
    create_membership(user, organization, "admin")

    actor =
      Core.Actor.build(
        user,
        [%{organization_id: organization.id, role: "admin"}],
        organization.id
      )

    %{actor: actor, organization: organization}
  end

  describe "начисление заработной платы" do
    test "ведомость строится по работающим сотрудникам", context do
      %{actor: actor, organization: organization} = context

      create_employee(actor, %{salary: Decimal.new("200000")})
      create_employee(actor, %{salary: Decimal.new("100000")})

      assert {:ok, accrual} =
               Accruals.build(organization.id, actor, ~D[2026-10-31], ~D[2026-10-01])

      loaded = Accruals.load(accrual.id, organization.id)
      assert length(loaded.lines) == 2

      # Начислено 200 000 и 100 000, к выплате — за вычетом удержаний.
      totals = Pulse.Posting.PayrollAccrual.totals(loaded)
      assert Decimal.equal?(totals.gross, Decimal.new("300000"))
    end

    test "проведение создаёт движения зарплаты и проводки", context do
      %{actor: actor, organization: organization} = context

      create_employee(actor, %{salary: Decimal.new("200000")})
      {:ok, accrual} = Accruals.build(organization.id, actor, ~D[2026-10-31], ~D[2026-10-01])

      loaded = Accruals.load(accrual.id, organization.id)
      assert {:ok, posted} = Posting.post(loaded, actor, Pulse.Posting.PayrollAccrual)
      assert posted.status == :posted

      movements = payroll_movements(loaded)
      kinds = Enum.map(movements, & &1.kind) |> Enum.uniq()
      assert :gross in kinds
      assert :ipn in kinds
      assert :opv in kinds
      assert :so in kinds

      # Проводки: начисление, удержания и взносы работодателя.
      entries = Pulse.Accounting.Entries.for_document(loaded)
      contents = Enum.map(entries, & &1.content)
      assert Enum.any?(contents, &(&1 =~ "Начислена"))
      assert Enum.any?(contents, &(&1 =~ "ИПН"))
      assert Enum.any?(contents, &(&1 =~ "работодателя"))
    end

    test "отмена проведения удаляет движения", context do
      %{actor: actor, organization: organization} = context

      create_employee(actor, %{salary: Decimal.new("200000")})
      {:ok, accrual} = Accruals.build(organization.id, actor, ~D[2026-10-31], ~D[2026-10-01])
      loaded = Accruals.load(accrual.id, organization.id)

      {:ok, posted} = Posting.post(loaded, actor, Pulse.Posting.PayrollAccrual)
      assert {:ok, draft} = Posting.unpost(posted, actor, Pulse.Posting.PayrollAccrual)
      assert draft.status == :draft
      assert payroll_movements(loaded) == []
    end
  end

  describe "выплата заработной платы" do
    test "выплата через банк списывает деньги и закрывает долг", context do
      %{actor: actor, organization: organization} = context

      create_employee(actor, %{salary: Decimal.new("200000")})
      {:ok, accrual} = Accruals.build(organization.id, actor, ~D[2026-10-31], ~D[2026-10-01])
      loaded = Accruals.load(accrual.id, organization.id)
      {:ok, _posted} = Posting.post(loaded, actor, Pulse.Posting.PayrollAccrual)

      account = create_bank_account(actor, %{name: "Зарплатный счёт"})
      fund_bank_account(actor, organization.id, account.id, "1000000")

      {:ok, statement} =
        create_payment(actor, %{
          doc_date: ~D[2026-11-05],
          number: "ВЗ-1",
          accrual_id: accrual.id,
          account_kind: :bank,
          bank_account_id: account.id,
          amount: Decimal.new("171375")
        })

      assert {:ok, posted} = Posting.post(statement, actor, Pulse.Posting.PayrollPayment)
      assert posted.status == :posted

      balance =
        Pulse.Settlements.cash_balance(organization.id, :bank, account.id, ~D[2026-11-05])

      assert Decimal.equal?(balance, Decimal.new("828625"))
    end

    test "выплата без денег отклоняется", context do
      %{actor: actor} = context

      account = create_bank_account(actor)

      {:ok, statement} =
        create_payment(actor, %{
          doc_date: ~D[2026-11-05],
          number: "ВЗ-2",
          account_kind: :bank,
          bank_account_id: account.id,
          amount: Decimal.new("500000")
        })

      assert {:error, message} = Posting.post(statement, actor, Pulse.Posting.PayrollPayment)
      assert message =~ "недостаточно денежных средств"
    end
  end

  describe "кадровые документы" do
    test "приём создаёт сотрудника и влияет на расчёт", context do
      %{actor: actor, organization: organization} = context

      person = create_person(actor)
      position = create_position(actor, %{salary: Decimal.new("300000")})

      {:ok, hiring} =
        HR.CadreDocument
        |> Ash.Changeset.for_create(:create, %{
          doc_date: ~D[2026-09-01],
          number: "ПР-1",
          kind: :hiring,
          person_id: person.id,
          position_id: position.id,
          salary: Decimal.new("300000")
        })
        |> Ash.Changeset.set_tenant(organization.id)
        |> Ash.create(actor: actor)

      assert {:ok, posted} = Pulse.HR.Posting.post(hiring, actor)
      assert posted.status == :posted

      # Сотрудник появился, оклад взят из документа.
      [employee] = HR.Employee |> Ash.read!(tenant: organization.id, authorize?: false)
      assert employee.salary |> Decimal.equal?(Decimal.new("300000"))

      # И расчёт за сентябрь видит нового сотрудника.
      assert {:ok, lines} = Accruals.build_lines(organization.id, ~D[2026-09-30])
      assert length(lines) == 1
    end

    test "увольнение закрывает сотрудника" do
      organization = create_organization(%{name: "Кадры-Орг"})
      user = create_user()
      create_membership(user, organization, "admin")

      actor =
        Core.Actor.build(
          user,
          [%{organization_id: organization.id, role: "admin"}],
          organization.id
        )

      employee = create_employee(actor, %{hire_date: ~D[2026-01-01]})

      {:ok, dismissal} =
        HR.CadreDocument
        |> Ash.Changeset.for_create(:create, %{
          doc_date: ~D[2026-10-31],
          number: "УВ-1",
          kind: :dismissal,
          employee_id: employee.id
        })
        |> Ash.Changeset.set_tenant(organization.id)
        |> Ash.create(actor: actor)

      assert {:ok, _posted} = Pulse.HR.Posting.post(dismissal, actor)

      reloaded = HR.Employee |> Ash.get!(employee.id, tenant: organization.id, authorize?: false)
      assert reloaded.status == :dismissed
      assert reloaded.dismissal_date == ~D[2026-10-31]

      # Отмена возвращает сотрудника к прежнему состоянию.
      assert {:ok, unposted} =
               Pulse.HR.Posting.unpost(
                 reloaded_document(dismissal, organization.id),
                 actor,
                 Pulse.HR.Posting
               )

      assert unposted.status == :draft
      back = HR.Employee |> Ash.get!(employee.id, tenant: organization.id, authorize?: false)
      assert back.status == :working
    end
  end

  describe "персональные данные" do
    test "ИИН хранится в базе зашифрованным" do
      organization = create_organization(%{name: "ПДн-Орг"})
      user = create_user()
      create_membership(user, organization, "admin")

      actor =
        Core.Actor.build(
          user,
          [%{organization_id: organization.id, role: "admin"}],
          organization.id
        )

      person = create_person(actor, %{iin: "990101500999"})

      # Значение в модели и в другом чтении — открытый текст.
      assert person.iin == "990101500999"
      reloaded = Person |> Ash.get!(person.id, tenant: organization.id, authorize?: false)
      assert reloaded.iin == "990101500999"

      # В самой колонке — шифротекст: сырой запрос не отдаёт ИИН.
      %{rows: [[raw]]} =
        Pulse.Repo.query!("SELECT iin FROM hr_people WHERE id = $1", [uuid_binary(person.id)])

      refute raw == "990101500999"
      refute String.contains?(to_string(raw), "990101500999")
    end
  end

  # --- вспомогательное -------------------------------------------------------

  defp payroll_movements(document) do
    type = Pulse.Accounting.Posting.document_type(document)

    Pulse.Ledger.PayrollMovement
    |> Ash.Query.filter(document_type == ^type and document_id == ^document.id)
    |> Ash.read!(tenant: document.organization_id, authorize?: false)
  end

  defp reloaded_document(document, organization_id) do
    HR.CadreDocument |> Ash.get!(document.id, tenant: organization_id, authorize?: false)
  end

  defp create_payment(actor, attrs) do
    Payroll.PaymentStatement
    |> Ash.Changeset.for_create(:create, attrs)
    |> Ash.Changeset.set_tenant(actor.organization_id)
    |> Ash.create(actor: actor)
  end

  # Начисляем деньги на счёт движением-поступлением, чтобы выплата
  # могла провестись: без остатка списание запрещено.
  defp fund_bank_account(actor, organization_id, account_id, amount) do
    {:ok, item} = create_income_item(actor)

    {:ok, document} =
      Pulse.Treasury.BankDocument
      |> Ash.Changeset.for_create(:create, %{
        doc_date: ~D[2026-11-01],
        number: "ФОНД-1",
        direction: :receipt,
        bank_account_id: account_id,
        cash_flow_item_id: item.id,
        amount: Decimal.new(amount)
      })
      |> Ash.Changeset.set_tenant(organization_id)
      |> Ash.create(actor: actor)

    {:ok, _posted} = Posting.post(document, actor, Pulse.Posting.TreasuryPayment)
    :ok
  end

  defp create_income_item(actor) do
    Pulse.Treasury.CashFlowItem
    |> Ash.Changeset.for_create(:create, %{
      code: "IN-TEST",
      name: "Поступление",
      kind: :receipt,
      account_code: "6280"
    })
    |> Ash.Changeset.set_tenant(actor.organization_id)
    |> Ash.create(actor: actor)
  end

  # UUID строкой → бинарник для сырого запроса.
  defp uuid_binary(uuid) do
    {:ok, binary} = Ecto.UUID.dump(uuid)
    binary
  end
end
