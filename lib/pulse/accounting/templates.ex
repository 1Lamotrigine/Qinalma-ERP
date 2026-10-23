defmodule Pulse.Accounting.Templates do
  @moduledoc """
  Построение проводок по шаблонам типовых операций (раздел 5.4 ТЗ).

  Шаблоны хранятся в БД (`Pulse.Accounting.EntryTemplate`), поэтому
  бухгалтер меняет счета без релиза. Модуль читает шаблон по виду
  операции и подставляет счета, субконто и суммы операции.

  Если шаблон не найден, возвращается ошибка: проведение без плана
  счетов бессмысленно, лучше явный отказ, чем проводка «наугад».
  """
  require Ash.Query

  alias Pulse.Accounting.EntryTemplate

  @doc """
  Строит проводки по шаблону операции.

  `attrs` — данные операции: `:amount`, `:content`, `:quantity`,
  `:currency_code`, `:amount_currency`, `:debit_subaccounts`,
  `:credit_subaccounts`. Шаблон даёт счета и, если операция их не
  задала, субконто.
  """
  @spec build(atom(), struct(), map()) :: {:ok, [map()]} | {:error, String.t()}
  def build(kind, document, attrs) do
    case fetch(kind) do
      {:ok, template} ->
        {:ok, [entry(template, document, attrs)]}

      {:error, error} ->
        {:error, error}
    end
  end

  @doc """
  Шаблон по виду операции в бухгалтерском учёте.
  """
  @spec fetch(atom()) :: {:ok, EntryTemplate.t()} | {:error, String.t()}
  def fetch(kind, ledger \\ :accounting) do
    query =
      EntryTemplate
      |> Ash.Query.filter(kind == ^kind and ledger == ^ledger)

    case Ash.read(query, authorize?: false) do
      {:ok, [template | _]} ->
        {:ok, template}

      {:ok, []} ->
        {:error, "не найден шаблон проводок для операции «#{kind}»"}

      {:error, error} ->
        {:error, "не удалось прочитать шаблон проводок: #{Exception.message(error)}"}
    end
  end

  @doc """
  Шаблон в виде `{debit_account_code, credit_account_code}`.

  Удобно для тестов и для проверки, что счета заполнены.
  """
  @spec accounts(atom()) :: {String.t(), String.t()} | nil
  def accounts(kind) do
    case fetch(kind) do
      {:ok, template} -> {template.debit_account_code, template.credit_account_code}
      _ -> nil
    end
  end

  defp entry(template, document, attrs) do
    %{
      debit_account_code: template.debit_account_code,
      credit_account_code: template.credit_account_code,
      amount: Map.fetch!(attrs, :amount),
      ledger: template.ledger,
      content: Map.get(attrs, :content),
      quantity: Map.get(attrs, :quantity),
      currency_code: Map.get(attrs, :currency_code),
      amount_currency: Map.get(attrs, :amount_currency),
      debit_subaccounts: subaccounts(attrs, :debit_subaccounts, template.debit_subaccount_codes),
      credit_subaccounts:
        subaccounts(attrs, :credit_subaccounts, template.credit_subaccount_codes),
      doc_date: document.doc_date,
      period: period(document.doc_date)
    }
  end

  defp subaccounts(attrs, key, template_codes) do
    case Map.get(attrs, key) do
      value when is_list(value) and value != [] -> value
      _ -> codes_to_subaccounts(template_codes)
    end
  end

  # Шаблон хранит коды видов субконто; значения подставляет операция,
  # поэтому здесь остаётся только вид без идентификатора.
  defp codes_to_subaccounts(codes) do
    Enum.map(codes, &%{"type" => &1, "id" => nil})
  end

  defp period(%Date{year: year, month: month}), do: %Date{year: year, month: month, day: 1}
end
