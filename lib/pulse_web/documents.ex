defmodule PulseWeb.Documents do
  @moduledoc """
  Реестр документов рабочей области: связь пунктов меню «Документы»
  с ресурсами Ash.

  Для каждого документа описаны:

    * `resource` — ресурс документа;
    * `rule` — правило проведения (`Pulse.Posting.Rule`);
    * `columns` — колонки журнала;
    * `row` — функция преобразования записи в строку журнала.

  Документы мультитенантны: все запросы идут с активной организацией
  актора. Проведение и отмена выполняются в транзакции
  (`Pulse.Accounting.Posting`), журнал после этого перечитывается.
  """

  alias Pulse.Accounting.Posting
  alias Pulse.Core
  alias Pulse.Purchasing
  alias Pulse.Sales
  require Ash.Query

  @doc """
  Спецификация документа по заголовку пункта меню.
  """
  @spec spec(String.t()) :: map() | nil
  def spec("Поступления ТМЗ и услуг"), do: receipt_spec()
  def spec("Реализации ТМЗ и услуг"), do: shipment_spec()
  def spec("Банковские расчетные документы"), do: bank_document_spec()
  def spec("Кассовые документы"), do: cash_document_spec()
  def spec("Журнал кадровых документов"), do: cadre_document_spec(nil)
  def spec("Приемы на работу в организации"), do: cadre_document_spec(:hiring)
  def spec("Кадровые перемещения организации"), do: cadre_document_spec(:transfer)
  def spec("Командировки организации"), do: cadre_document_spec(:trip)
  def spec("Увольнения из организаций"), do: cadre_document_spec(:dismissal)
  def spec("Начисления зарплаты сотрудникам организаций"), do: accrual_spec()
  def spec("Выплаты и перечисления зарплаты"), do: payment_statement_spec()
  def spec(_title), do: nil

  @doc """
  Все заголовки журналов документов, которые уже реализованы.
  """
  @spec titles() :: [String.t()]
  def titles do
    [
      "Поступления ТМЗ и услуг",
      "Реализации ТМЗ и услуг",
      "Банковские расчетные документы",
      "Кассовые документы",
      "Журнал кадровых документов",
      "Приемы на работу в организации",
      "Кадровые перемещения организации",
      "Командировки организации",
      "Увольнения из организаций",
      "Начисления зарплаты сотрудникам организаций",
      "Выплаты и перечисления зарплаты"
    ]
  end

  @doc """
  Загружает документы для журнала.
  """
  @spec list(map(), struct()) :: {:ok, [map()]} | {:error, String.t()}
  def list(spec, actor) do
    if is_nil(actor.organization_id) do
      {:ok, []}
    else
      spec.resource
      |> base_filter(spec)
      |> Ash.Query.sort(doc_date: :desc)
      |> Ash.read(actor: actor, tenant: actor.organization_id, load: spec.load)
      |> case do
        {:ok, records} -> {:ok, Enum.map(records, fn record -> spec.row.(record) end)}
        {:error, %Ash.Error.Forbidden{}} -> {:ok, []}
        {:error, error} -> {:error, Exception.message(error)}
      end
    end
  end

  @doc """
  Загружает документ с табличной частью.
  """
  @spec fetch(map(), String.t(), struct()) :: {:ok, struct()} | {:error, term()}
  def fetch(spec, document_id, actor) do
    spec.resource
    |> Ash.Query.filter(id == ^document_id)
    |> Ash.read_one(actor: actor, tenant: actor.organization_id, load: spec.load)
    |> case do
      {:ok, nil} -> {:error, :not_found}
      {:ok, document} -> {:ok, document}
      {:error, %Ash.Error.Forbidden{}} -> {:error, :forbidden}
      {:error, error} -> {:error, error}
    end
  end

  @doc """
  Проводит документ.
  """
  @spec post(struct(), struct(), map()) :: {:ok, struct()} | {:error, String.t()}
  def post(document, actor, spec) do
    post(document, actor, spec, posting_module(spec))
  end

  defp post(document, actor, spec, module) do
    rule = spec.rule

    case module.post(document, actor, rule) do
      {:ok, posted} -> {:ok, posted}
      {:error, error} -> {:error, error_message(error)}
    end
  end

  @doc """
  Отменяет проведение документа.
  """
  @spec unpost(struct(), struct(), map()) :: {:ok, struct()} | {:error, String.t()}
  def unpost(document, actor, spec) do
    rule = spec.rule

    case posting_module(spec).unpost(document, actor, rule) do
      {:ok, draft} -> {:ok, draft}
      {:error, error} -> {:error, error_message(error)}
    end
  end

  # Кадровые документы проводятся своим циклом: они не пишут проводок
  # и не двигают деньги — у них нет финансовых последствий.
  defp posting_module(%{posting: :hr}), do: Pulse.HR.Posting
  defp posting_module(_spec), do: Posting

  # Ограничение журнала: например, только приёмы на работу.
  defp base_filter(query, %{base_filter: filter}), do: Ash.Query.filter(query, ^filter)
  defp base_filter(query, _spec), do: query

  @doc """
  Движения ТМЗ документа для формы.

  Показываются только складские движения: деньги и расчёты видны
  в своих журналах, а не в карточке складского документа.
  """
  @spec movements(struct()) :: [struct()]
  def movements(document) do
    document
    |> Posting.movements()
    |> Enum.filter(&match?(%Pulse.Ledger.StockMovement{}, &1))
  end

  defp error_message(error) when is_binary(error), do: error

  defp error_message(%{errors: errors}) do
    Enum.map_join(errors, "; ", &Exception.message/1)
  end

  defp error_message(error), do: Exception.message(error)

  # ---------------------------------------------------------------------------
  # Поступление ТМЗ и услуг
  # ---------------------------------------------------------------------------

  defp receipt_spec do
    %{
      title: "Поступления ТМЗ и услуг",
      resource: Purchasing.Receipt,
      rule: Pulse.Posting.PurchasingReceipt,
      load: [:lines],
      columns: [
        %{key: :doc_date, label: "Дата"},
        %{key: :number, label: "Номер"},
        %{key: :amount, label: "Сумма"},
        %{key: :status, label: "Статус"}
      ],
      row: fn document ->
        %{
          id: document.id,
          doc_date: format_date(document.doc_date),
          number: document.number,
          amount: format_amount(document),
          status: status_label(document.status)
        }
      end
    }
  end

  # ---------------------------------------------------------------------------
  # Реализация ТМЗ и услуг
  # ---------------------------------------------------------------------------

  defp shipment_spec do
    %{
      title: "Реализации ТМЗ и услуг",
      resource: Sales.Shipment,
      rule: Pulse.Posting.SalesShipment,
      load: [:lines],
      columns: [
        %{key: :doc_date, label: "Дата"},
        %{key: :number, label: "Номер"},
        %{key: :amount, label: "Сумма"},
        %{key: :status, label: "Статус"}
      ],
      row: fn document ->
        %{
          id: document.id,
          doc_date: format_date(document.doc_date),
          number: document.number,
          amount: format_amount(document),
          status: status_label(document.status)
        }
      end
    }
  end

  # ---------------------------------------------------------------------------
  # Банковские расчётные документы
  # ---------------------------------------------------------------------------

  defp bank_document_spec do
    %{
      title: "Банковские расчетные документы",
      resource: Pulse.Treasury.BankDocument,
      rule: Pulse.Posting.TreasuryPayment,
      load: [:bank_account],
      amount_field: :amount,
      columns: [
        %{key: :doc_date, label: "Дата"},
        %{key: :number, label: "Номер"},
        %{key: :direction, label: "Вид"},
        %{key: :account, label: "Счёт"},
        %{key: :amount, label: "Сумма"},
        %{key: :status, label: "Статус"}
      ],
      row: fn document ->
        %{
          id: document.id,
          doc_date: format_date(document.doc_date),
          number: document.number,
          direction: direction_label(document.direction),
          account: account_label(document),
          amount: format_decimal(document.amount),
          status: status_label(document.status)
        }
      end
    }
  end

  # ---------------------------------------------------------------------------
  # Кассовые документы
  # ---------------------------------------------------------------------------

  defp cash_document_spec do
    %{
      title: "Кассовые документы",
      resource: Pulse.Treasury.CashDocument,
      rule: Pulse.Posting.TreasuryPayment,
      load: [:cash_desk],
      amount_field: :amount,
      columns: [
        %{key: :doc_date, label: "Дата"},
        %{key: :number, label: "Номер"},
        %{key: :direction, label: "Вид"},
        %{key: :account, label: "Касса"},
        %{key: :amount, label: "Сумма"},
        %{key: :status, label: "Статус"}
      ],
      row: fn document ->
        %{
          id: document.id,
          doc_date: format_date(document.doc_date),
          number: document.number,
          direction: direction_label(document.direction),
          account: account_label(document),
          amount: format_decimal(document.amount),
          status: status_label(document.status)
        }
      end
    }
  end

  # ---------------------------------------------------------------------------
  # Кадровые документы (этап 8)
  # ---------------------------------------------------------------------------

  defp cadre_document_spec(kind) do
    base = %{
      title: cadre_title(kind),
      resource: Pulse.HR.CadreDocument,
      rule: Pulse.HR.Posting,
      posting: :hr,
      load: [:employee, :person, :position, :department],
      columns: [
        %{key: :doc_date, label: "Дата"},
        %{key: :number, label: "Номер"},
        %{key: :kind, label: "Вид"},
        %{key: :employee, label: "Сотрудник"},
        %{key: :status, label: "Статус"}
      ],
      row: fn document ->
        %{
          id: document.id,
          doc_date: format_date(document.doc_date),
          number: document.number,
          kind: Pulse.HR.CadreDocument.kind_title(document.kind),
          employee: cadre_employee(document),
          status: status_label(document.status)
        }
      end
    }

    if kind, do: Map.put(base, :base_filter, kind: kind), else: base
  end

  defp cadre_title(nil), do: "Журнал кадровых документов"
  defp cadre_title(kind), do: Pulse.HR.CadreDocument.kind_title(kind)

  defp cadre_employee(%{employee: %Ash.NotLoaded{}}), do: "—"
  defp cadre_employee(%{employee: nil}), do: "—"

  defp cadre_employee(%{employee: %{person: %Ash.NotLoaded{}}} = document),
    do: document.employee.id

  defp cadre_employee(%{employee: %{person: nil}} = document), do: document.employee.id
  defp cadre_employee(%{employee: %{person: person}}), do: Pulse.HR.Person.full_name(person)
  defp cadre_employee(_document), do: "—"

  # ---------------------------------------------------------------------------
  # Начисление заработной платы (этап 8)
  # ---------------------------------------------------------------------------

  defp accrual_spec do
    %{
      title: "Начисления зарплаты сотрудникам организаций",
      resource: Pulse.Payroll.Accrual,
      rule: Pulse.Posting.PayrollAccrual,
      load: [:lines],
      columns: [
        %{key: :doc_date, label: "Дата"},
        %{key: :number, label: "Номер"},
        %{key: :period, label: "Период"},
        %{key: :gross, label: "Начислено", align: :right},
        %{key: :status, label: "Статус"}
      ],
      row: fn document ->
        %{
          id: document.id,
          doc_date: format_date(document.doc_date),
          number: document.number,
          period: format_period(document.period),
          gross: format_decimal(Pulse.Posting.PayrollAccrual.totals(document).gross),
          status: status_label(document.status)
        }
      end
    }
  end

  # ---------------------------------------------------------------------------
  # Выплата заработной платы (этап 8)
  # ---------------------------------------------------------------------------

  defp payment_statement_spec do
    %{
      title: "Выплаты и перечисления зарплаты",
      resource: Pulse.Payroll.PaymentStatement,
      rule: Pulse.Posting.PayrollPayment,
      load: [:bank_account, :cash_desk],
      columns: [
        %{key: :doc_date, label: "Дата"},
        %{key: :number, label: "Номер"},
        %{key: :account_kind, label: "Способ"},
        %{key: :amount, label: "Сумма"},
        %{key: :status, label: "Статус"}
      ],
      row: fn document ->
        %{
          id: document.id,
          doc_date: format_date(document.doc_date),
          number: document.number,
          account_kind: payroll_account_kind(document.account_kind),
          amount: format_decimal(document.amount),
          status: status_label(document.status)
        }
      end
    }
  end

  defp payroll_account_kind(:bank), do: "Банк"
  defp payroll_account_kind(:cash), do: "Касса"
  defp payroll_account_kind(kind), do: to_string(kind)

  defp format_period(%Date{} = date), do: "#{date.month}.#{date.year}"
  defp format_period(nil), do: "—"

  @doc """
  Спецификация формы создания документа по заголовку пункта меню.

  Для документов без табличной части (кадровые, начисление, выплата):
  форма собирается реестром справочников, потому что поля простые.
  """
  @spec form_spec(String.t()) :: map() | nil
  def form_spec("Журнал кадровых документов"), do: cadre_form_spec(nil)
  def form_spec("Приемы на работу в организации"), do: cadre_form_spec(:hiring)
  def form_spec("Кадровые перемещения организации"), do: cadre_form_spec(:transfer)
  def form_spec("Командировки организации"), do: cadre_form_spec(:trip)
  def form_spec("Увольнения из организаций"), do: cadre_form_spec(:dismissal)
  def form_spec("Начисления зарплаты сотрудникам организаций"), do: accrual_form_spec()
  def form_spec("Выплаты и перечисления зарплаты"), do: payment_form_spec()
  def form_spec(_title), do: nil

  defp cadre_form_spec(kind) do
    base = %{
      title: cadre_title(kind || :hiring),
      resource: Pulse.HR.CadreDocument,
      tenant?: true,
      fields: [
        %{name: :doc_date, label: "Дата", type: :date, required: true},
        %{name: :number, label: "Номер", type: :text},
        %{
          name: :kind,
          label: "Вид документа",
          type: :select,
          options: Pulse.HR.CadreDocument.kinds(),
          required: true
        },
        %{name: :employee_id, label: "Сотрудник", type: :ref, resource: Pulse.HR.Employee},
        %{name: :person_id, label: "Физлицо (при приёме)", type: :ref, resource: Pulse.HR.Person},
        %{name: :position_id, label: "Должность", type: :ref, resource: Pulse.HR.Position},
        %{name: :department_id, label: "Подразделение", type: :ref, resource: Core.Department},
        %{name: :salary, label: "Оклад", type: :number},
        %{name: :trip_from, label: "Командировка с", type: :date},
        %{name: :trip_to, label: "Командировка по", type: :date},
        %{name: :trip_destination, label: "Место командировки", type: :text},
        %{name: :reason, label: "Основание", type: :textarea}
      ]
    }

    if kind, do: Map.put(base, :defaults, %{kind: kind}), else: base
  end

  defp accrual_form_spec do
    %{
      title: "Начисление зарплаты",
      resource: Pulse.Payroll.Accrual,
      tenant?: true,
      fields: [
        %{name: :doc_date, label: "Дата", type: :date, required: true},
        %{name: :period, label: "За месяц", type: :date},
        %{name: :number, label: "Номер", type: :text},
        %{name: :comment, label: "Комментарий", type: :textarea}
      ]
    }
  end

  defp payment_form_spec do
    %{
      title: "Выплата заработной платы",
      resource: Pulse.Payroll.PaymentStatement,
      tenant?: true,
      fields: [
        %{name: :doc_date, label: "Дата", type: :date, required: true},
        %{name: :number, label: "Номер", type: :text},
        %{
          name: :accrual_id,
          label: "Расчётная ведомость",
          type: :ref,
          resource: Pulse.Payroll.Accrual
        },
        %{
          name: :account_kind,
          label: "Способ",
          type: :select,
          options: [{"Банк", :bank}, {"Касса", :cash}],
          required: true
        },
        %{
          name: :bank_account_id,
          label: "Банковский счёт",
          type: :ref,
          resource: Pulse.Treasury.BankAccount
        },
        %{name: :cash_desk_id, label: "Касса", type: :ref, resource: Pulse.Treasury.CashDesk},
        %{name: :amount, label: "Сумма", type: :number, required: true}
      ]
    }
  end

  @doc """
  Подпись статуса документа.
  """
  @spec status_label(atom()) :: String.t()
  def status_label(:draft), do: "Не проведен"
  def status_label(:posted), do: "Проведен"
  def status_label(:cancelled), do: "Отменен"

  @doc """
  Подпись направления движения денег.
  """
  @spec direction_label(atom()) :: String.t()
  def direction_label(:receipt), do: "Поступление"
  def direction_label(:expense), do: "Списание"

  defp format_date(%Date{} = date), do: Date.to_string(date)
  defp format_date(nil), do: nil

  defp format_amount(%{lines: %Ash.NotLoaded{}}), do: "—"

  defp format_amount(%{lines: lines}) do
    lines
    |> Enum.reduce(Decimal.new(0), fn line, acc -> Decimal.add(acc, line_amount(line)) end)
    |> Decimal.round(2)
    |> Decimal.to_string()
  end

  defp format_decimal(nil), do: "—"

  defp format_decimal(value) do
    value
    |> Decimal.round(2)
    |> Decimal.to_string()
  end

  defp account_label(%{bank_account: %Ash.NotLoaded{}}), do: nil
  defp account_label(%{bank_account: nil}), do: nil
  defp account_label(%{bank_account: account}), do: account.name
  defp account_label(%{cash_desk: %Ash.NotLoaded{}}), do: nil
  defp account_label(%{cash_desk: nil}), do: nil
  defp account_label(%{cash_desk: desk}), do: desk.name
  defp account_label(_document), do: nil

  defp line_amount(line), do: line.amount || Decimal.mult(line.quantity, line.price)
end
