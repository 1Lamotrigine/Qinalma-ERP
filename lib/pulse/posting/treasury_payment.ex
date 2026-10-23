defmodule Pulse.Posting.TreasuryPayment do
  @moduledoc """
  Правило проведения банковского и кассового документа.

  Оплата влияет на три регистра сразу:

    * деньги — остаток кассы или счёта (`CashMovement`);
    * взаиморасчёты — долг контрагента и зачёт аванса
      (`SettlementMovement`);
    * бухгалтерский учёт — проводка по статье движения денег.

  Направление документа задаёт сторону: поступление приходует деньги
  и закрывает долг покупателя, списание — наоборот.
  """
  @behaviour Pulse.Posting.Rule

  alias Pulse.Accounting.Templates
  alias Pulse.Ledger.CashMovement
  alias Pulse.Ledger.SettlementMovement

  @impl true
  def movements(document, _context) do
    {:ok, [cash_movement(document)]}
  end

  @impl true
  def ledger_movements(document, _context) do
    with {:ok, settlements} <- settlement_movements(document) do
      {:ok,
       [
         {CashMovement, [cash_movement(document)]},
         {SettlementMovement, settlements}
       ]}
    end
  end

  @impl true
  def entries(document, _context) do
    attrs = %{
      amount: document.amount,
      content: content(document),
      ledger: :accounting,
      debit_subaccounts: subaccounts(document, :debit),
      credit_subaccounts: subaccounts(document, :credit)
    }

    Templates.build(template_kind(document), document, attrs)
  end

  @impl true
  def lock_keys(document, _mode) do
    [{:cash, account_id(document)}]
  end

  @impl true
  def check_balances(document) do
    if document.direction == :expense do
      balance =
        Pulse.Settlements.cash_balance(
          document.organization_id,
          account_kind(document),
          account_id(document),
          document.doc_date
        )

      if Decimal.compare(balance, document.amount) == :lt do
        {:error, "недостаточно денежных средств: нужно #{document.amount}, доступно #{balance}"}
      else
        :ok
      end
    else
      :ok
    end
  end

  @doc """
  Движение денег по документу.
  """
  @spec cash_movement(struct()) :: map()
  def cash_movement(document) do
    %{
      document_type: document_type(document),
      document_id: document.id,
      account_kind: account_kind(document),
      account_id: account_id(document),
      record_type: document.direction,
      period: period(document.doc_date),
      doc_date: document.doc_date,
      amount: document.amount,
      currency_id: document.currency_id,
      amount_currency: document.amount,
      cash_flow_item_id: document.cash_flow_item_id,
      counterparty_id: document.counterparty_id,
      contract_id: document.contract_id
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

  # Расчёты ведутся только при указанном контрагенте: без него оплата
  # не создаёт долга, например перечисление налогов.
  defp settlement_movements(document) do
    if document.counterparty_id do
      side = settlement_side(document)

      movement = %{
        document_type: document_type(document),
        document_id: document.id,
        counterparty_id: document.counterparty_id,
        contract_id: document.contract_id,
        direction: settlement_direction(document),
        side: side,
        period: period(document.doc_date),
        doc_date: document.doc_date,
        amount: document.amount,
        currency_id: document.currency_id,
        amount_currency: document.amount,
        due_date: nil
      }

      # Аванс зачитывается сам: долг и оплата лежат на одной стороне,
      # поэтому их суммы взаимно погашаются в сальдо.
      {:ok, [movement]}
    else
      {:ok, []}
    end
  end

  # Оплата относится к той же стороне, что и долг, который она закрывает:
  # поступление денег — дебиторская задолженность покупателя,
  # списание — кредиторская задолженность поставщику.
  defp settlement_side(%{direction: :receipt}), do: :debit
  defp settlement_side(%{direction: :expense}), do: :credit

  # Долг, который создаёт оплата: поступление закрывает дебиторскую
  # задолженность, списание — кредиторскую.
  defp settlement_direction(_document), do: :payment

  defp template_kind(document) do
    case {account_kind(document), document.direction} do
      {:cash, :receipt} -> :cash_receipt
      {:cash, :expense} -> :cash_payment
      {:bank, :receipt} -> :bank_receipt
      {:bank, :expense} -> :bank_payment
    end
  end

  defp account_kind(%Pulse.Treasury.BankDocument{}), do: :bank
  defp account_kind(%Pulse.Treasury.CashDocument{}), do: :cash

  defp account_id(%Pulse.Treasury.BankDocument{bank_account_id: id}), do: id
  defp account_id(%Pulse.Treasury.CashDocument{cash_desk_id: id}), do: id

  defp content(%{direction: :receipt}), do: "Поступление денежных средств"
  defp content(%{direction: :expense}), do: "Выдача денежных средств"

  # Субконто ставится по контрагенту на обе стороны проводки:
  # аналитика расчётов нужна и по дебету, и по кредиту.
  defp subaccounts(document, _side) do
    if document.counterparty_id do
      [%{"type" => "counterparty", "id" => document.counterparty_id}]
    else
      []
    end
  end
end
