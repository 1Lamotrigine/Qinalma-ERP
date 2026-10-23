defmodule Pulse.HR.CadreDocument do
  @moduledoc """
  Кадровый документ: приём, перемещение, увольнение, командировка
  (раздел 5.5 ТЗ).

  Одна таблица с полем `kind` вместо четырёх почти одинаковых: все
  кадровые документы описывают изменение состояния сотрудника, и
  различаются лишь тем, какое поле меняют. Так проще поддерживать
  общий жизненный цикл (черновик → проведён) и аудит.

  Проведение меняет карточку сотрудника (`Pulse.HR.Posting`): приём
  назначает должность и оклад, перемещение — новую должность или
  подразделение, увольнение закрывает сотрудника, командировка пишет
  срок поездки. Отмена возвращает предыдущее состояние по снимку.
  """
  use Pulse.Accounting.Document,
    domain: Pulse.HR,
    table: "hr_cadre_documents",
    create_accept: [
      :doc_date,
      :number,
      :currency_id,
      :rate,
      :comment,
      :kind,
      :employee_id,
      :person_id,
      :position_id,
      :department_id,
      :salary,
      :trip_from,
      :trip_to,
      :trip_destination,
      :reason
    ],
    update_accept: [
      :doc_date,
      :number,
      :currency_id,
      :rate,
      :comment,
      :kind,
      :employee_id,
      :person_id,
      :position_id,
      :department_id,
      :salary,
      :trip_from,
      :trip_to,
      :trip_destination,
      :reason
    ]

  actions do
    update :post do
      accept([])
      require_atomic?(false)
      change({Pulse.HR.Changes.Post, rule: Pulse.HR.Posting})
    end

    update :unpost do
      accept([])
      require_atomic?(false)
      change({Pulse.HR.Changes.Unpost, rule: Pulse.HR.Posting})
    end

    update :mark_posted do
      accept([:status, :posted_at, :posted_by, :employee_id, :snapshot])
      require_atomic?(false)
    end

    update :mark_draft do
      accept([:status, :posted_at, :posted_by])
      require_atomic?(false)
    end
  end

  attributes do
    attribute :kind, :atom do
      allow_nil?(false)
      constraints(one_of: [:hiring, :transfer, :dismissal, :trip])
      public?(true)
    end

    attribute :employee_id, :uuid do
      allow_nil?(true)
      public?(true)
    end

    # Физлицо указывается в приказе о приёме: сотрудник по нему ещё не создан.
    attribute :person_id, :uuid do
      allow_nil?(true)
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

    attribute :salary, :decimal do
      allow_nil?(true)
      public?(true)
    end

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

    attribute :reason, :string do
      allow_nil?(true)
      public?(true)
    end

    # Снимок карточки сотрудника до проведения — для отмены.
    attribute :snapshot, :map do
      allow_nil?(true)
      public?(false)
    end
  end

  relationships do
    belongs_to :employee, Pulse.HR.Employee do
      define_attribute?(false)
      public?(true)
    end

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

  identities do
    identity(:unique_number, [:number])
  end

  @kinds [
    hiring: "Приём на работу",
    transfer: "Кадровое перемещение",
    dismissal: "Увольнение",
    trip: "Командировка"
  ]

  @doc """
  Виды кадровых документов для форм и фильтров.
  """
  @spec kinds() :: [{String.t(), atom()}]
  def kinds, do: Enum.map(@kinds, fn {key, title} -> {title, key} end)

  @doc """
  Название вида документа.
  """
  @spec kind_title(atom()) :: String.t()
  def kind_title(kind), do: Keyword.get(@kinds, kind, to_string(kind))
end
