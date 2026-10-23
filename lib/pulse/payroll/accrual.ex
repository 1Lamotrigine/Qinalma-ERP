defmodule Pulse.Payroll.Accrual do
  @moduledoc """
  Начисление заработной платы сотрудникам (раздел 5.5 ТЗ).

  Расчётная ведомость: строки — расчёт по каждому сотруднику, суммы
  считает `Pulse.Payroll.Calculator` по параметрам закона на дату
  документа. Проведение пишет движения регистра зарплаты и проводки
  (`Pulse.Posting.PayrollAccrual`).
  """
  use Pulse.Accounting.Document,
    domain: Pulse.Payroll,
    table: "payroll_accruals",
    create_accept: [
      :doc_date,
      :number,
      :currency_id,
      :rate,
      :comment,
      :period
    ],
    update_accept: [
      :doc_date,
      :number,
      :currency_id,
      :rate,
      :comment,
      :period
    ]

  actions do
    update :post do
      accept([])
      require_atomic?(false)
      change({Pulse.Accounting.Changes.Post, rule: Pulse.Posting.PayrollAccrual})
    end

    update :unpost do
      accept([])
      require_atomic?(false)
      change({Pulse.Accounting.Changes.Unpost, rule: Pulse.Posting.PayrollAccrual})
    end

    update :mark_posted do
      accept([:status, :posted_at, :posted_by])
      require_atomic?(false)
    end

    update :mark_draft do
      accept([:status, :posted_at, :posted_by])
      require_atomic?(false)
    end
  end

  attributes do
    # Месяц, за который начисляется зарплата.
    attribute :period, :date do
      allow_nil?(true)
      public?(true)
    end
  end

  relationships do
    has_many :lines, Pulse.Payroll.AccrualLine do
      destination_attribute(:document_id)
      public?(true)
      sort(line_no: :asc)
    end
  end

  @doc """
  Документ со строками и сотрудниками — для отчётов и проведения.
  """
  @spec with_lines(t(), String.t()) :: struct()
  def with_lines(document, organization_id) do
    document
    |> Ash.load!([lines: [employee: [:person]]], tenant: organization_id, authorize?: false)
  end
end
