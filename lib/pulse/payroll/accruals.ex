defmodule Pulse.Payroll.Accruals do
  @moduledoc """
  Заполнение и чтение расчётных ведомостей (раздел 5.5 ТЗ).

  Ведомость наполняется по работающим сотрудникам на дату документа:
  оклад каждого умножается на расчёт по параметрам закона
  (`Pulse.Payroll.Calculator`). Расчёт фиксируется в строках — проведение
  его не повторяет, поэтому смена ставки не переписывает прошлые месяцы.
  """
  require Ash.Query

  alias Pulse.HR.Employee
  alias Pulse.Payroll.Accrual
  alias Pulse.Payroll.AccrualLine
  alias Pulse.Payroll.Calculator

  @doc """
  Возвращает сотрудников, которым начисляется зарплата на дату.
  """
  @spec employees_for(String.t(), Date.t()) :: [Employee.t()]
  def employees_for(organization_id, date) do
    Employee
    |> Ash.Query.filter(status == :working)
    |> Ash.Query.sort(hire_date: :asc)
    |> Ash.read(tenant: organization_id, authorize?: false)
    |> case do
      {:ok, employees} -> Enum.filter(employees, &Employee.working_on?(&1, date))
      _ -> []
    end
  end

  @doc """
  Считает расчёт по сотруднику на дату.

  Возвращает `{:ok, атрибуты строки}` либо ошибку: если оклад не задан
  или нет параметров закона.
  """
  @spec calculate_line(Employee.t(), String.t(), Date.t()) ::
          {:ok, map()} | {:error, String.t()}
  def calculate_line(employee, organization_id, date) do
    gross = employee.salary

    cond do
      is_nil(gross) or Decimal.equal?(gross, 0) ->
        {:error, "у сотрудника не задан оклад"}

      true ->
        with {:ok, rates} <- Calculator.rates_on(date),
             {:ok, result} <- Calculator.calculate(gross, rates, date) do
          {:ok,
           %{
             organization_id: organization_id,
             employee_id: employee.id,
             gross: result.gross,
             opv: result.opv,
             vosms: result.vosms,
             ipn: result.ipn,
             so: result.so,
             opvr: result.opvr,
             oosms: result.oosms,
             net: result.net
           }}
        end
    end
  end

  @doc """
  Строит строки ведомости по работающим сотрудникам.

  Возвращает `{:ok, [атрибуты строк]}` либо список ошибок по сотрудникам
  без оклада — их видно в интерфейсе, а не молча пропущено.
  """
  @spec build_lines(String.t(), Date.t()) :: {:ok, [map()]} | {:error, [String.t()]}
  def build_lines(organization_id, date) do
    employees = employees_for(organization_id, date)

    results = Enum.map(employees, &calculate_line(&1, organization_id, date))

    case Enum.filter(results, &match?({:error, _}, &1)) do
      [] -> {:ok, Enum.map(results, fn {:ok, line} -> line end)}
      errors -> {:error, Enum.map(errors, fn {:error, message} -> message end)}
    end
  end

  @doc """
  Создаёт ведомость со строками по работающим сотрудникам.

  Даты документа и периода задаются: ведомость — за месяц.
  """
  @spec build(String.t(), struct(), Date.t(), Date.t()) ::
          {:ok, Accrual.t()} | {:error, term()}
  def build(organization_id, actor, doc_date, period) do
    with {:ok, lines} <- build_lines(organization_id, doc_date) do
      attrs = %{
        doc_date: doc_date,
        period: period,
        number: "ЗП-#{Date.to_string(period)}",
        comment: "Начисление заработной платы за #{period}"
      }

      with {:ok, accrual} <- create(organization_id, actor, attrs),
           {:ok, _lines} <- create_lines(organization_id, actor, accrual, lines) do
        {:ok, accrual}
      end
    end
  end

  @doc """
  Ведомость со строками и сотрудниками.
  """
  @spec load(String.t(), String.t()) :: Accrual.t() | nil
  def load(accrual_id, organization_id) do
    Accrual
    |> Ash.Query.filter(id == ^accrual_id)
    |> Ash.Query.load([:lines, lines: [:employee]])
    |> Ash.read_one(tenant: organization_id, authorize?: false)
    |> case do
      {:ok, accrual} -> accrual
      _ -> nil
    end
  end

  @doc """
  Ведомости организации за период.
  """
  @spec list(String.t(), Date.t(), Date.t()) :: [Accrual.t()]
  def list(organization_id, from, to) do
    Accrual
    |> Ash.Query.filter(doc_date >= ^from and doc_date <= ^to)
    |> Ash.Query.sort(doc_date: :desc)
    |> Ash.read(tenant: organization_id, authorize?: false)
    |> case do
      {:ok, accruals} -> accruals
      _ -> []
    end
  end

  defp create(organization_id, actor, attrs) do
    Accrual
    |> Ash.Changeset.for_create(:create, attrs)
    |> Ash.Changeset.set_tenant(organization_id)
    |> Ash.create(actor: actor, tenant: organization_id)
  end

  defp create_lines(organization_id, actor, accrual, lines) do
    lines
    |> Enum.with_index(1)
    |> Enum.reduce_while({:ok, []}, fn {line, index}, {:ok, acc} ->
      attrs = Map.merge(line, %{document_id: accrual.id, line_no: index})

      AccrualLine
      |> Ash.Changeset.for_create(:create, attrs)
      |> Ash.Changeset.set_tenant(organization_id)
      |> Ash.create(actor: actor, tenant: organization_id)
      |> case do
        {:ok, record} -> {:cont, {:ok, acc ++ [record]}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end
end
