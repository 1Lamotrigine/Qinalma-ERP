defmodule Pulse.Posting.PayrollPayment do
  @moduledoc """
  Правило проведения выплаты заработной платы.

  Выплата — это расход денег: списывается банковский счёт или касса,
  пишется движение регистра зарплаты вида `payment` и проводка
  Дт 3350 Кт 1030/1010 (`Pulse.Posting.PayrollPayment`).

  Если ведомость ссылается на расчётную ведомость, движение по
  зарплате пишется по каждому сотруднику (его сумма к выплате);
  иначе — одной суммой по документу.
  """
  @behaviour Pulse.Posting.Rule

  require Ash.Query

  alias Pulse.Accounting.Templates
  alias Pulse.Ledger.CashMovement
  alias Pulse.Ledger.PayrollMovement

  @impl true
  def movements(document, _context) do
    {:ok, [cash_movement(document)]}
  end

  @impl true
  def ledger_movements(document, _context) do
    {:ok,
     [
       {CashMovement, [cash_movement(document)]},
       {PayrollMovement, payroll_movements(document)}
     ]}
  end

  @impl true
  def entries(document, _context) do
    attrs = %{
      amount: document.amount,
      content: "Выплата заработной платы",
      ledger: :accounting
    }

    Templates.build(:payroll_payment, document, attrs)
  end

  @impl true
  def lock_keys(document, _mode), do: [{:cash, account_id(document)}]

  @impl true
  def check_balances(document) do
    balance =
      Pulse.Settlements.cash_balance(
        document.organization_id,
        document.account_kind,
        account_id(document),
        document.doc_date
      )

    if Decimal.compare(balance, document.amount) == :lt do
      {:error, "недостаточно денежных средств: нужно #{document.amount}, доступно #{balance}"}
    else
      :ok
    end
  end

  @doc """
  Движение денег по выплате.
  """
  @spec cash_movement(struct()) :: map()
  def cash_movement(document) do
    %{
      document_type: document_type(document),
      document_id: document.id,
      account_kind: document.account_kind,
      account_id: account_id(document),
      record_type: :expense,
      period: period(document.doc_date),
      doc_date: document.doc_date,
      amount: document.amount,
      currency_id: document.currency_id,
      amount_currency: document.amount,
      cash_flow_item_id: nil,
      counterparty_id: nil,
      contract_id: nil
    }
  end

  @doc """
  Тип документа в регистрах.
  """
  @spec document_type(struct()) :: String.t()
  def document_type(document), do: Pulse.Accounting.Posting.document_type(document)

  @doc """
  Период — первый день месяца документа.
  """
  @spec period(Date.t()) :: Date.t()
  def period(%Date{year: year, month: month}), do: %Date{year: year, month: month, day: 1}

  defp payroll_movements(document) do
    document
    |> accrual_lines()
    |> Enum.map(&line_movement(document, &1))
  end

  defp line_movement(document, line) do
    %{
      document_type: document_type(document),
      document_id: document.id,
      document_line_id: line.id,
      employee_id: line.employee_id,
      kind: :payment,
      period: period(document.doc_date),
      doc_date: document.doc_date,
      amount: line.net,
      currency_id: document.currency_id,
      amount_currency: line.net
    }
  end

  # Движение по зарплате требует сотрудника: без расчётной ведомости
  # выплата пишется только движением денег и проводкой.
  defp accrual_lines(document) do
    case document.accrual_id do
      nil -> []
      accrual_id -> load_lines(document, accrual_id)
    end
  end

  defp load_lines(document, accrual_id) do
    Pulse.Payroll.Accrual
    |> Ash.Query.filter(id == ^accrual_id)
    |> Ash.Query.load([:lines])
    |> Ash.read_one(tenant: document.organization_id, authorize?: false)
    |> case do
      {:ok, %{lines: lines}} -> lines
      _ -> []
    end
  end

  defp account_id(document) do
    case document.account_kind do
      :bank -> document.bank_account_id
      :cash -> document.cash_desk_id
    end
  end
end
