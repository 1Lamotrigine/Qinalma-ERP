defmodule Pulse.Tax.Rates do
  @moduledoc """
  Выбор законодательного параметра на дату (раздел 5.5 ТЗ).

  Ставки и пороги не зашиты в код: модуль читает `Pulse.Tax.StatutoryRate`
  и находит запись, в чей интервал действия попадает дата.

  Если записи нет, возвращается ошибка, а не «значение по умолчанию»:
  молча подставить неверную ставку хуже, чем явно отказать.
  """
  require Ash.Query

  alias Pulse.Tax.StatutoryRate

  @typedoc """
  Найденная ставка: значение и период, из которого оно взято.
  """
  @type rate :: %{
          code: String.t(),
          value: Decimal.t(),
          valid_from: Date.t(),
          valid_to: Date.t() | nil,
          note: String.t() | nil
        }

  @doc """
  Значение параметра на дату.

  Возвращает `{:ok, rate}` либо `{:error, причина}`.
  """
  @spec fetch(String.t(), Date.t()) :: {:ok, rate()} | {:error, String.t()}
  def fetch(code, date) do
    StatutoryRate
    |> Ash.Query.filter(code == ^code)
    |> Ash.Query.filter(valid_from <= ^date)
    |> Ash.Query.sort(valid_from: :desc)
    |> Ash.read(authorize?: false)
    |> case do
      {:ok, [rate | _rest]} -> validate(rate, date)
      {:ok, []} -> {:error, "не задано значение параметра «#{code}» на #{Date.to_string(date)}"}
      {:error, error} -> {:error, Exception.message(error)}
    end
  end

  @doc """
  Значение параметра или `nil`, если его нет.

  Удобно там, где отсутствие значения не ошибка: например, при
  заполнении формы значением по умолчанию.
  """
  @spec get(String.t(), Date.t()) :: Decimal.t() | nil
  def get(code, date) do
    case fetch(code, date) do
      {:ok, rate} -> rate.value
      {:error, _reason} -> nil
    end
  end

  @doc """
  Значение параметра на дату или явная ошибка.

  Для расчётов, где без ставки нельзя: НДС, зарплата.
  """
  @spec fetch!(String.t(), Date.t()) :: Decimal.t()
  def fetch!(code, date) do
    case fetch(code, date) do
      {:ok, rate} -> rate.value
      {:error, reason} -> raise ArgumentError, reason
    end
  end

  @doc """
  Все значения кода по периодам — для экрана налоговых настроек.
  """
  @spec history(String.t()) :: [StatutoryRate.t()]
  def history(code) do
    StatutoryRate
    |> Ash.Query.filter(code == ^code)
    |> Ash.Query.sort(valid_from: :desc)
    |> Ash.read(authorize?: false)
    |> case do
      {:ok, rates} -> rates
      _ -> []
    end
  end

  @doc """
  Все параметры, действующие на дату, по одному значению на код.

  Используется сводкой налоговых настроек: видно, с какими ставками
  работает система прямо сейчас.
  """
  @spec current(Date.t()) :: [rate()]
  def current(date) do
    StatutoryRate
    |> Ash.Query.filter(valid_from <= ^date)
    |> Ash.Query.sort(code: :asc, valid_from: :desc)
    |> Ash.read(authorize?: false)
    |> case do
      {:ok, rates} -> latest_per_code(rates, date)
      _ -> []
    end
  end

  @doc """
  Ставка НДС на дату в долях единицы: 12 % → 0.12.

  Ставки в справочнике хранятся в процентах, как в Налоговом кодексе,
  а расчёты удобнее вести долями.
  """
  @spec vat_share(Date.t()) :: {:ok, Decimal.t()} | {:error, String.t()}
  def vat_share(date) do
    case fetch("vat_rate", date) do
      {:ok, rate} -> {:ok, Decimal.div(rate.value, 100)}
      {:error, reason} -> {:error, reason}
    end
  end

  # Значение параметра на дату: берём запись с самым поздним началом,
  # у которой период ещё не закончился.
  defp validate(%{valid_to: nil} = rate, _date), do: {:ok, rate}

  defp validate(%{valid_to: valid_to} = rate, date) do
    if Date.compare(valid_to, date) == :lt do
      {:error, "значение параметра «#{rate.code}» истекло #{Date.to_string(valid_to)}"}
    else
      {:ok, rate}
    end
  end

  defp latest_per_code(rates, date) do
    rates
    |> Enum.group_by(& &1.code)
    |> Enum.map(fn {_code, list} -> Enum.find(list, &valid_on?(&1, date)) end)
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&to_rate/1)
    |> Enum.sort_by(& &1.code)
  end

  defp valid_on?(%{valid_to: nil}, _date), do: true

  defp valid_on?(%{valid_to: valid_to}, date), do: Date.compare(valid_to, date) != :lt

  defp to_rate(record) do
    %{
      code: record.code,
      value: record.value,
      valid_from: record.valid_from,
      valid_to: record.valid_to,
      note: record.note
    }
  end
end
