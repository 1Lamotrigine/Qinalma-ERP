defmodule Pulse.Core.Permissions do
  @moduledoc """
  Кэш матрицы прав в ETS.

  Правило: `{роль, ресурс, действие}` → `allowed?`. Запрет по умолчанию:
  если комбинации нет в матрице, действие не разрешено.

  Таблица заполняется из БД при старте приложения (`reload/0`) и
  перезагружается после изменений матрицы.

  В test-окружении кэш отключён (`config :pulse, :cache_permissions, false`):
  проверка идёт напрямую в БД, что согласуется с sandbox-транзакциями.
  """
  use GenServer
  require Ash.Query

  @table :pulse_permissions

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Дочерний процесс супервизии; в test-окружении подменяется на пустой Agent.
  """
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    if cache_enabled?() do
      %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}}
    else
      %{id: __MODULE__, start: {Agent, :start_link, [fn -> :ok end]}}
    end
  end

  @doc """
  Проверяет, разрешено ли действие роли на ресурс.
  """
  @spec allowed?(String.t() | nil, String.t(), String.t()) :: boolean()
  def allowed?(nil, _resource, _action), do: false
  def allowed?("admin", _resource, _action), do: true

  def allowed?(role, resource, action) do
    if cache_enabled?() do
      case :ets.lookup(@table, {role, resource, action}) do
        [{{^role, ^resource, ^action}, true}] -> true
        _ -> false
      end
    else
      matrix_row?(role, resource, action)
    end
  end

  @doc """
  Возвращает отсортированный список разрешённых строк матрицы.

  При включённом кэше читает из ETS, иначе — из БД.
  """
  @spec dump() :: [{String.t(), String.t(), String.t()}]
  def dump do
    if cache_enabled?() do
      :ets.tab2list(@table)
      |> Enum.map(fn {{role, resource, action}, true} -> {role, resource, action} end)
      |> Enum.sort()
    else
      case Ash.read(Pulse.Core.RolePermission, domain: Pulse.Core, authorize?: false) do
        {:ok, rows} ->
          rows
          |> Enum.filter(& &1.allowed?)
          |> Enum.map(&{&1.role, &1.resource, &1.action})
          |> Enum.sort()

        _ ->
          []
      end
    end
  end

  @doc """
  Перезагружает кэш из БД. Ошибка БД не роняет приложение: кэш очищается.
  """
  @spec reload() :: :ok
  def reload do
    if cache_enabled?() and Process.whereis(__MODULE__) do
      GenServer.call(__MODULE__, :reload)
    else
      :ok
    end
  end

  defp cache_enabled? do
    Application.get_env(:pulse, :cache_permissions, true)
  end

  defp matrix_row?(role, resource, action) do
    query =
      Ash.Query.filter(
        Pulse.Core.RolePermission,
        role == ^role and resource == ^resource and action == ^action
      )

    case Ash.read(query, domain: Pulse.Core, authorize?: false) do
      {:ok, [row | _]} -> row.allowed?
      _ -> false
    end
  end

  @impl true
  def init(_opts) do
    table = :ets.new(@table, [:set, :public, :named_table])
    load_from_db(table)
    {:ok, table}
  end

  @impl true
  def handle_call(:reload, _from, table) do
    :ets.delete_all_objects(table)
    load_from_db(table)
    {:reply, :ok, table}
  end

  defp load_from_db(table) do
    case Ash.read(Pulse.Core.RolePermission, domain: Pulse.Core, authorize?: false) do
      {:ok, rows} ->
        for row <- rows do
          :ets.insert(table, {{row.role, row.resource, row.action}, row.allowed?})
        end

        :ok

      {:error, _error} ->
        # Таблицы ещё нет (миграции) — работаем с пустой матрицей.
        :ok
    end
  end
end
