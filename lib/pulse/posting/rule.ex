defmodule Pulse.Posting.Rule do
  @moduledoc """
  Поведение правила проведения документа.

  Правило — это чистая функция «документ → движения и проводки»: она не
  ходит в БД и тестируется без неё. Всё, что нужно для расчёта (остатки,
  средняя себестоимость), правило получает в `Pulse.Posting.Context`,
  который раннер наполняет до вызова.
  """
  alias Pulse.Posting.Context

  @doc """
  Движения ТМЗ по документу.

  Возвращает `{:ok, [map]}` или `{:error, причина}`. Каждый элемент —
  карта атрибутов `Pulse.Ledger.StockMovement` без `organization_id`
  (его подставляет раннер).
  """
  @callback movements(document :: struct(), context :: Context.t()) ::
              {:ok, [map()]} | {:error, term()}

  @doc """
  Проводки бухгалтерского учёта по документу.

  Возвращает `{:ok, [map]}` или `{:error, причина}`. Каждый элемент —
  карта атрибутов `Pulse.Accounting.JournalEntry` без служебных полей
  (`organization_id`, `document_type`, `document_id`): их подставляет
  `Pulse.Accounting.Entries`.

  Необязательный колбэк: документ без бухгалтерских проводок (например,
  складской) его не реализует — раннер тогда ничего не пишет.
  """
  @callback entries(document :: struct(), context :: Context.t()) ::
              {:ok, [map()]} | {:error, term()}

  @doc """
  Движения регистров по документу.

  Возвращает `{:ok, [{module, [map]}]}` — список пар «ресурс регистра,
  движения». Раннер записывает их в той же транзакции, что движения ТМЗ,
  проводки и статус.

  Необязательный колбэк: документ, который пишет только в один регистр,
  может его не реализовывать — тогда используется `movements/2`.
  """
  @callback ledger_movements(document :: struct(), context :: Context.t()) ::
              {:ok, [{module(), [map()]}]} | {:error, term()}

  @doc """
  Ключи блокировок `pg_advisory_xact_lock` помимо организации.

  Возвращает список `{тип, идентификатор}`, например
  `{:warehouse, uuid}` или `{:nomenclature, uuid}`.
  """
  @callback lock_keys(document :: struct(), mode :: :post | :unpost) :: [tuple()]

  @doc """
  Проверка остатков для расходных документов.

  Вызывается до формирования движений; `:ok` либо `{:error, причина}`.
  """
  @callback check_balances(document :: struct()) :: :ok | {:error, term()}

  @doc """
  Проводки документа или `{:ok, []}`, если правило их не формирует.
  """
  @spec entries_or_none(module(), struct(), Context.t()) :: {:ok, [map()]}
  def entries_or_none(rule, document, context) do
    if function_exported?(rule, :entries, 2) do
      rule.entries(document, context)
    else
      {:ok, []}
    end
  end

  @doc """
  Движения регистров документа.

  Если правило реализует `ledger_movements/2`, берётся оттуда; иначе
  движения ТМЗ из `movements/2` пишутся в `Pulse.Ledger.StockMovement`.
  """
  @spec ledger_movements(module(), struct(), Context.t()) :: {:ok, [{module(), [map]}]}
  def ledger_movements(rule, document, context) do
    if function_exported?(rule, :ledger_movements, 2) do
      rule.ledger_movements(document, context)
    else
      case rule.movements(document, context) do
        {:ok, movements} -> {:ok, [{Pulse.Ledger.StockMovement, movements}]}
        {:error, error} -> {:error, error}
      end
    end
  end

  @optional_callbacks entries: 2, ledger_movements: 2
end
