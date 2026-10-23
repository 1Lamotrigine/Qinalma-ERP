defmodule Pulse.HR.Employee do
  @moduledoc """
  Сотрудник организации (раздел 5.5 ТЗ).

  Сотрудник — связка физлица с организацией: должность, подразделение,
  оклад и статус. Кадровые документы (приём, перемещение, увольнение)
  меняют его текущее состояние, а сами остаются в истории.

  Банковские реквизиты для выплаты зарплаты — персональные данные и
  хранятся зашифрованными.
  """
  use Pulse.HR.Resource, table: "hr_employees"

  actions do
    defaults([:read, :destroy])

    create :create do
      accept([
        :person_id,
        :position_id,
        :department_id,
        :hire_date,
        :salary,
        :bank_account,
        :status
      ])

      validate(present([:person_id]))
      validate(one_of(:status, [:working, :dismissed]))
    end

    update :update do
      accept([
        :person_id,
        :position_id,
        :department_id,
        :hire_date,
        :salary,
        :bank_account,
        :status,
        :dismissal_date
      ])
    end
  end

  attributes do
    attribute :person_id, :uuid do
      allow_nil?(false)
      public?(true)
    end

    attribute :position_id, :uuid do
      allow_nil?(true)
      public?(true)
    end

    attribute :department_id, :uuid do
      allow_nil?(true)
      public?(true)
    end

    attribute :hire_date, :date do
      allow_nil?(true)
      public?(true)
    end

    attribute :dismissal_date, :date do
      allow_nil?(true)
      public?(true)
    end

    # Текущий оклад сотрудника.
    attribute :salary, :decimal do
      allow_nil?(true)
      public?(true)
    end

    # Банковские реквизиты для перечисления — персональные данные.
    attribute :bank_account, Pulse.Types.Encrypted do
      allow_nil?(true)
      public?(true)
    end

    attribute :status, :atom do
      allow_nil?(false)
      default(:working)
      constraints(one_of: [:working, :dismissed])
      public?(true)
    end

    # Текущая командировка: срок и место последней поездки.
    attribute :trip_from, :date do
      allow_nil?(true)
      public?(true)
    end

    attribute :trip_to, :date do
      allow_nil?(true)
      public?(true)
    end

    attribute :trip_destination, :string do
      allow_nil?(true)
      public?(true)
    end
  end

  relationships do
    belongs_to :person, Pulse.HR.Person do
      define_attribute?(false)
      public?(true)
    end

    belongs_to :position, Pulse.HR.Position do
      define_attribute?(false)
      public?(true)
    end

    belongs_to :department, Pulse.Core.Department do
      define_attribute?(false)
      public?(true)
    end
  end

  @doc """
  Сотрудник работает на дату: принят и не уволен раньше неё.
  """
  @spec working_on?(t(), Date.t()) :: boolean()
  def working_on?(employee, date) do
    hired? = is_nil(employee.hire_date) or Date.compare(employee.hire_date, date) != :gt

    dismissed? =
      not is_nil(employee.dismissal_date) and Date.compare(employee.dismissal_date, date) != :gt

    hired? and not dismissed?
  end
end
