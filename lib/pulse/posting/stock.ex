defmodule Pulse.Posting.Stock do
  @moduledoc """
  Остатки ТМЗ и средняя взвешенная себестоимость.

  Остаток на дату = сумма движений по складу и номенклатуре
  с датой документа не позже указанной. Себестоимость расхода —
  средняя взвешенная по остатку: `стоимость остатка / количество остатка`.
  """
  alias Pulse.Ledger.StockMovement
  require Ash.Query

  @typedoc """
  Остаток: количество, стоимость и средняя себестоимость единицы.
  """
  @type balance :: %{
          quantity: Decimal.t(),
          cost: Decimal.t(),
          unit_cost: Decimal.t()
        }

  @doc """
  Остаток по складу и номенклатуре на дату.
  """
  @spec balance(Pulse.Posting.Context.t(), String.t(), String.t(), Date.t()) :: balance()
  def balance(context, warehouse_id, nomenclature_id, date) do
    query =
      StockMovement
      |> Ash.Query.filter(
        warehouse_id == ^warehouse_id and nomenclature_id == ^nomenclature_id and
          doc_date <= ^date
      )

    case Ash.read(query, tenant: context.organization_id, authorize?: false) do
      {:ok, movements} -> sum(movements)
      _ -> empty()
    end
  end

  @doc """
  Сводит движения в остаток.

  Чистая функция: используется и в тестах, и при чтении из регистра.
  """
  @spec sum([StockMovement.t()]) :: balance()
  def sum(movements) do
    {quantity, cost} =
      Enum.reduce(movements, {Decimal.new(0), Decimal.new(0)}, fn movement, {qty, cost} ->
        sign = if movement.record_type == :receipt, do: 1, else: -1

        {
          Decimal.add(qty, Decimal.mult(sign, movement.quantity)),
          Decimal.add(cost, Decimal.mult(sign, movement.cost))
        }
      end)

    %{
      quantity: quantity,
      cost: cost,
      unit_cost: unit_cost(quantity, cost)
    }
  end

  @doc """
  Средняя себестоимость единицы.

  При нулевом или отрицательном остатке себестоимость нулевая: расход
  без остатка запрещён проверкой остатков, поэтому это защита от
  деления на ноль, а не рабочий сценарий.
  """
  @spec unit_cost(Decimal.t(), Decimal.t()) :: Decimal.t()
  def unit_cost(quantity, cost) do
    if Decimal.compare(quantity, 0) == :gt do
      Decimal.div(cost, quantity)
    else
      Decimal.new(0)
    end
  end

  @doc """
  Пустой остаток.
  """
  @spec empty() :: balance()
  def empty do
    %{quantity: Decimal.new(0), cost: Decimal.new(0), unit_cost: Decimal.new(0)}
  end
end
