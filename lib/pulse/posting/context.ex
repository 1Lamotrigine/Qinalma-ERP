defmodule Pulse.Posting.Context do
  @moduledoc """
  Данные, нужные правилу проведения: актор, организация и склады.

  Остатки и себестоимость правило запрашивает через функции этого
  модуля — они читают регистр движений. Чистая часть правила
  (расчёт сумм по строкам) остаётся тестируемой без БД: подставьте
  контекст с подготовленными остатками.
  """
  alias Pulse.Ledger.StockMovement
  alias Pulse.Posting.Stock

  @enforce_keys [:organization_id]
  defstruct [:actor, :organization_id, :stock]

  @type t :: %__MODULE__{
          actor: struct() | nil,
          organization_id: String.t(),
          stock: module()
        }

  @doc """
  Собирает контекст для документа.

  `:stock` — модуль расчёта остатков; по умолчанию читает регистр.
  В тестах подменяется заглушкой, чтобы правило считалось без БД.
  """
  @spec build(struct(), struct() | nil, keyword()) :: t()
  def build(document, actor, opts \\ []) do
    %__MODULE__{
      actor: actor,
      organization_id: document.organization_id,
      stock: Keyword.get(opts, :stock, Stock)
    }
  end

  @doc """
  Остаток и средняя себестоимость по складу и номенклатуре на дату.
  """
  @spec balance(t(), String.t(), String.t(), Date.t()) :: Stock.balance()
  def balance(%__MODULE__{stock: stock} = context, warehouse_id, nomenclature_id, date) do
    stock.balance(context, warehouse_id, nomenclature_id, date)
  end

  @doc false
  def movement_module, do: StockMovement
end
