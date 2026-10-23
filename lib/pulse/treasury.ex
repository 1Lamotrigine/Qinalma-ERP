defmodule Pulse.Treasury do
  @moduledoc """
  Домен денежных средств: банк, касса, статьи движения денег
  и остатки.

  Документы домена (банковские и кассовые) — обычные документы учёта
  (`Pulse.Accounting.Document`): проведение пишет движения денег,
  проводки и меняет статус в одной транзакции.
  """
  use Ash.Domain, otp_app: :pulse, extensions: [AshPaperTrail.Domain]

  resources do
    resource Pulse.Treasury.CashFlowItem do
      define(:list_cash_flow_items, action: :read)
    end

    resource Pulse.Treasury.BankAccount do
      define(:list_bank_accounts, action: :read)
    end

    resource Pulse.Treasury.CashDesk do
      define(:list_cash_desks, action: :read)
    end

    resource Pulse.Treasury.BankDocument do
      define(:list_bank_documents, action: :read)
    end

    resource Pulse.Treasury.CashDocument do
      define(:list_cash_documents, action: :read)
    end

    paper_trail do
      include_versions?(true)
    end
  end

  require Ash.Query

  @doc """
  Движения денег за период по направлению — для отчётов о поступлении
  и расходе средств.

  Возвращает строки с номером документа и названием кассы или счёта:
  отчёт читается человеком, идентификаторы ему не нужны.
  """
  @spec cash_flow(String.t(), :receipt | :expense, Date.t(), Date.t()) :: [map()]
  def cash_flow(organization_id, direction, from, to) do
    Pulse.Ledger.CashMovement
    |> Ash.Query.filter(record_type == ^direction)
    |> Ash.Query.filter(doc_date >= ^from and doc_date <= ^to)
    |> Ash.Query.sort(doc_date: :asc, inserted_at: :asc)
    |> Ash.read(tenant: organization_id, authorize?: false)
    |> case do
      {:ok, movements} -> Enum.map(movements, &decorate(organization_id, &1))
      _ -> []
    end
  end

  @doc """
  Движения по кассам за период — для кассовой книги.

  В кассовую книгу попадают только кассовые движения: банковские
  операции отражаются в выписке, а не в кассе.
  """
  @spec cash_book(String.t(), Date.t(), Date.t()) :: [map()]
  def cash_book(organization_id, from, to) do
    Pulse.Ledger.CashMovement
    |> Ash.Query.filter(account_kind == :cash)
    |> Ash.Query.filter(doc_date >= ^from and doc_date <= ^to)
    |> Ash.Query.sort(doc_date: :asc, inserted_at: :asc)
    |> Ash.read(tenant: organization_id, authorize?: false)
    |> case do
      {:ok, movements} -> Enum.map(movements, &decorate(organization_id, &1))
      _ -> []
    end
  end

  @doc """
  Название кассы или банковского счёта по идентификатору.
  """
  @spec account_name(String.t(), :cash | :bank, String.t()) :: String.t()
  def account_name(organization_id, :cash, account_id) do
    case Ash.get(Pulse.Treasury.CashDesk, account_id, tenant: organization_id, authorize?: false) do
      {:ok, desk} -> desk.name
      _ -> account_id
    end
  end

  def account_name(organization_id, :bank, account_id) do
    case Ash.get(Pulse.Treasury.BankAccount, account_id,
           tenant: organization_id,
           authorize?: false
         ) do
      {:ok, account} -> account.name
      _ -> account_id
    end
  end

  # Дополняет движение данными документа и счёта для отчёта.
  defp decorate(organization_id, movement) do
    %{
      movement: movement,
      doc_date: movement.doc_date,
      amount: movement.amount,
      record_type: movement.record_type,
      account_name: account_name(organization_id, movement.account_kind, movement.account_id),
      document_number: document_number(organization_id, movement),
      content: content(movement)
    }
  end

  # Номер документа-регистратора: движения ссылаются на него по типу
  # и идентификатору.
  defp document_number(organization_id, movement) do
    resource =
      case movement.document_type do
        "treasury.bank_document" -> Pulse.Treasury.BankDocument
        "treasury.cash_document" -> Pulse.Treasury.CashDocument
        _ -> nil
      end

    case resource &&
           Ash.get(resource, movement.document_id,
             tenant: organization_id,
             authorize?: false
           ) do
      {:ok, document} -> document.number
      _ -> nil
    end
  end

  defp content(%{record_type: :receipt}), do: "Поступление"
  defp content(%{record_type: :expense}), do: "Выдача"
end
