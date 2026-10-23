defmodule Pulse.Accounting.Recalculation do
  @moduledoc """
  Пересчёт себестоимости за месяц (раздел 5.3 ТЗ).

  Средняя взвешенная себестоимость зависит от порядка движений: расход
  до поступления считается по меньшему остатку, чем расход после него.
  Поэтому проведение задним числом меняет себестоимость последующих
  расходов — и её нужно пересчитать.

  Алгоритм месяца:

    1. взять все движения ТМЗ месяца по складу и номенклатуре;
    2. идти по ним в порядке даты и времени записи;
    3. после каждого прихода пересчитывать среднюю себестоимость;
    4. расход переоценивать по текущей средней себестоимости.

  Пересчёт идёт только внутри открытого месяца: закрытый период
  зафиксирован, его себестоимость не меняется.
  """

  alias Pulse.Ledger.StockMovement

  require Ash.Query

  @doc """
  Пересчитывает себестоимость расходов за месяц.

  Возвращает `{:ok, %{updated: count, periods: [...]}}` — сколько
  движений переоценено и по каким складам.
  """
  @spec recalculate_month(String.t(), Date.t()) :: {:ok, map()} | {:error, term()}
  def recalculate_month(organization_id, period) do
    {from, to} = Pulse.Accounting.Totals.period_bounds(period)

    case movements(organization_id, from, to) do
      {:ok, movements} ->
        updated =
          movements
          |> Enum.group_by(&{&1.warehouse_id, &1.nomenclature_id})
          |> Enum.flat_map(fn {key, rows} -> recalculate_group(key, rows) end)

        {:ok, %{updated: length(updated), period: period}}

      {:error, error} ->
        {:error, error}
    end
  end

  @doc """
  Пересчитывает себестоимость по складу и номенклатуре за месяц.

  Возвращает список обновлённых движений расхода.
  """
  @spec recalculate_group({String.t(), String.t()}, [StockMovement.t()]) :: [StockMovement.t()]
  def recalculate_group(_key, rows) do
    {_balance, updated} =
      rows
      |> Enum.sort_by(&{&1.doc_date, &1.inserted_at})
      |> Enum.reduce({empty_balance(), []}, fn movement, {balance, updated} ->
        case movement.record_type do
          :receipt ->
            {add_receipt(balance, movement), updated}

          :expense ->
            {new_movement, updated?} = revalue(movement, balance)

            {subtract_expense(balance, new_movement),
             if(updated?, do: updated ++ [new_movement], else: updated)}
        end
      end)

    updated
  end

  @doc """
  Себестоимость единицы по текущему остатку.
  """
  @spec unit_cost(map()) :: Decimal.t()
  def unit_cost(%{quantity: quantity, cost: cost}) do
    if Decimal.compare(quantity, 0) == :gt do
      Decimal.div(cost, quantity)
    else
      Decimal.new(0)
    end
  end

  defp movements(organization_id, from, to) do
    StockMovement
    |> Ash.Query.filter(doc_date >= ^from and doc_date <= ^to)
    |> Ash.Query.sort(doc_date: :asc, inserted_at: :asc)
    |> Ash.read(tenant: organization_id, authorize?: false)
  end

  # Расход переоценивается по средней себестоимости остатка на момент
  # движения. Движение пишется только если стоимость изменилась.
  defp revalue(movement, balance) do
    cost = Decimal.mult(unit_cost(balance), movement.quantity)

    if Decimal.equal?(cost, movement.cost) do
      {movement, false}
    else
      {updated, _result} = update_cost(movement, cost)
      {updated, true}
    end
  end

  defp update_cost(movement, cost) do
    movement
    |> Ash.Changeset.for_update(:revalue, %{cost: cost})
    |> Ash.Changeset.set_tenant(movement.organization_id)
    |> Ash.update(authorize?: false)
    |> case do
      {:ok, updated} -> {updated, :ok}
      {:error, _error} -> {%{movement | cost: cost}, :error}
    end
  end

  defp add_receipt(balance, movement) do
    %{
      quantity: Decimal.add(balance.quantity, movement.quantity),
      cost: Decimal.add(balance.cost, movement.cost)
    }
  end

  defp subtract_expense(balance, movement) do
    %{
      quantity: Decimal.sub(balance.quantity, movement.quantity),
      cost: Decimal.sub(balance.cost, movement.cost)
    }
  end

  defp empty_balance, do: %{quantity: Decimal.new(0), cost: Decimal.new(0)}
end
