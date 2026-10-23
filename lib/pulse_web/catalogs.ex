defmodule PulseWeb.Catalogs do
  @moduledoc """
  Реестр справочников рабочей области: связь пунктов меню «Справочники»
  с ресурсами Ash.

  Для каждого справочника описаны:

    * `resource` — ресурс Ash (`Pulse.Catalog.*` или `Pulse.Core.*`);
    * `tenant?` — нужна ли активная организация (мультитенантность);
    * `fields` — поля формы элемента (тип, подпись, обязательность);
    * `columns` — колонки журнала;
    * `row` — функция преобразования записи в строку журнала.

  Функции `list/2`, `form/3`, `fetch/3` и `options/2` инкапсулируют
  работу с Ash: мультитенантность, актора и обработку запрета политики
  (нет прав — пустой журнал, а не ошибка экрана).
  """

  alias Pulse.Catalog
  alias Pulse.Core
  require Ash.Query

  @legal_kinds [{"Юридическое лицо", :legal}, {"Физическое лицо", :individual}]
  @nomenclature_kinds [{"Товар", :product}, {"Услуга", :service}, {"Работа", :work}]
  @vat_rates [{"Без НДС", :none}, {"10%", :ten}, {"12%", :twelve}]
  @yes_no [{"Да", true}, {"Нет", false}]
  @cash_flow_kinds [{"Поступление", :receipt}, {"Выдача", :expense}]
  @account_kinds [
    {"Активный", :active},
    {"Пассивный", :passive},
    {"Активно-пассивный", :active_passive}
  ]
  @template_kinds [
    {"Поступление ТМЗ и услуг", :receipt_tmz},
    {"Реализация ТМЗ и услуг", :shipment_tmz},
    {"Поступление услуг", :receipt_service},
    {"Реализация услуг", :shipment_service},
    {"Поступление в кассу", :cash_receipt},
    {"Выплата из кассы", :cash_payment},
    {"Поступление на банковский счёт", :bank_receipt},
    {"Списание с банковского счёта", :bank_payment},
    {"Начисление заработной платы", :payroll_accrual},
    {"Удержание ИПН", :payroll_ipn},
    {"Удержание ОПВ и ВОСМС", :payroll_opv},
    {"Взносы и отчисления работодателя", :payroll_employer},
    {"Выплата заработной платы", :payroll_payment}
  ]

  @doc """
  Спецификация справочника по заголовку пункта меню; `nil`, если пункт
  не является реализованным справочником.
  """
  @spec spec(String.t()) :: map() | nil
  def spec("Организации"), do: organization_spec()
  def spec("Подразделения организаций"), do: department_spec()
  def spec("Контрагенты"), do: counterparty_spec()
  def spec("Договоры контрагентов"), do: contract_spec()
  def spec("Номенклатура"), do: nomenclature_spec()
  def spec("Склады (места хранения)"), do: warehouse_spec()
  def spec("Классификатор единиц измерения"), do: unit_spec()
  def spec("Валюты"), do: currency_spec()
  def spec("Банки"), do: bank_spec()
  def spec("План счетов бухгалтерского учета"), do: account_spec()
  def spec("Виды субконто"), do: subaccount_type_spec()
  def spec("Типовые операции"), do: entry_template_spec()
  def spec("Статьи движения денежных средств"), do: cash_flow_item_spec()
  def spec("Банковские счета"), do: bank_account_spec()
  def spec("Кассы"), do: cash_desk_spec()
  def spec("Сведения о ставках налогов, сборов и отчислений"), do: statutory_rate_spec()
  def spec("Ставки НДС"), do: vat_rate_spec()
  def spec("Физические лица"), do: person_spec()
  def spec("Сотрудники"), do: employee_spec()
  def spec("Должности организаций"), do: position_spec()
  def spec(_title), do: nil

  @doc """
  Загружает записи справочника для строки журнала.
  """
  @spec list(map(), struct()) :: {:ok, [map()]} | {:error, String.t()}
  def list(spec, actor) do
    if spec.tenant? and is_nil(actor.organization_id) do
      {:ok, []}
    else
      spec.resource
      |> base_filter(spec)
      |> sort_query(spec)
      |> Ash.read(read_opts(spec, actor))
      |> case do
        {:ok, records} -> {:ok, Enum.map(records, fn record -> spec.row.(record) end)}
        # Политика запретила — в журнале пусто, а не ошибка экрана.
        {:error, %Ash.Error.Forbidden{}} -> {:ok, []}
        {:error, error} -> {:error, Exception.message(error)}
      end
    end
  end

  @doc """
  Форма создания (record == nil) или редактирования элемента справочника.

  Возвращает `Phoenix.HTML.Form`, готовую для `<.form for={...}>`.
  """
  @spec form(map(), struct() | nil, struct()) :: Phoenix.HTML.Form.t()
  def form(spec, nil, actor) do
    spec.resource
    |> AshPhoenix.Form.for_create(:create, form_opts(spec, actor))
    |> Phoenix.Component.to_form()
  end

  def form(spec, record, actor) do
    record
    |> AshPhoenix.Form.for_update(:update, form_opts(spec, actor))
    |> Phoenix.Component.to_form()
  end

  @doc """
  Загружает один элемент по идентификатору для редактирования.
  """
  @spec fetch(map(), String.t(), struct()) :: {:ok, struct()} | {:error, term()}
  def fetch(spec, record_id, actor) do
    spec.resource
    |> Ash.Query.filter(id == ^record_id)
    |> Ash.read_one(read_opts(spec, actor))
    |> case do
      {:ok, nil} -> {:error, :not_found}
      {:ok, record} -> {:ok, record}
      {:error, %Ash.Error.Forbidden{}} -> {:error, :forbidden}
      {:error, error} -> {:error, error}
    end
  end

  @doc """
  Опции выпадающих списков для ссылочных полей `{id, представление}`.
  """
  @spec options(module(), struct()) :: [{String.t(), String.t()}]
  def options(resource, actor) do
    multitenant? = not is_nil(Ash.Resource.Info.multitenancy_strategy(resource))

    opts =
      [actor: actor] ++
        if(multitenant?, do: [tenant: actor.organization_id], else: [])

    if multitenant? and is_nil(actor.organization_id) do
      []
    else
      case resource |> sort_options(actor) |> Ash.read(opts) do
        {:ok, records} -> Enum.map(records, &{&1.id, display(resource, &1)})
        _ -> []
      end
    end
  end

  # Список для выпадающего поля: сортируем по имени, если оно есть у
  # ресурса (у физлиц имя собирается из фамилии и имени).
  defp sort_options(resource, _actor) do
    fields = Ash.Resource.Info.attributes(resource) |> Enum.map(& &1.name)

    cond do
      :name in fields -> Ash.Query.sort(resource, name: :asc)
      :last_name in fields -> Ash.Query.sort(resource, last_name: :asc, first_name: :asc)
      true -> resource
    end
  end

  @doc """
  Представление записи ресурса для ссылочных полей и списков.
  """
  @spec display(module(), struct()) :: String.t()
  def display(Catalog.Currency, record), do: "#{record.code} — #{record.name}"
  def display(Catalog.Unit, record), do: "#{record.code} — #{record.name}"
  def display(Pulse.HR.Person, record), do: Pulse.HR.Person.full_name(record)
  def display(_resource, record), do: to_string(record.name)

  defp form_opts(spec, actor) do
    [actor: actor, as: "catalog"] ++ tenant_opt(spec, actor)
  end

  defp read_opts(spec, actor) do
    [actor: actor, load: spec.load] ++ tenant_opt(spec, actor)
  end

  defp sort_query(query, %{sort: sort}), do: Ash.Query.sort(query, sort)
  defp sort_query(query, _spec), do: query

  # Ограничение списка справочника (например, только ставки НДС).
  defp base_filter(query, %{base_filter: filter}), do: Ash.Query.filter(query, ^filter)
  defp base_filter(query, _spec), do: query

  defp tenant_opt(%{tenant?: false}, _actor), do: []

  defp tenant_opt(_spec, actor), do: [tenant: actor.organization_id]

  # ---------------------------------------------------------------------------
  # Организации (глобальный справочник, доступен по членству)
  # ---------------------------------------------------------------------------

  defp organization_spec do
    %{
      title: "Организации",
      resource: Core.Organization,
      tenant?: false,
      sort: [name: :asc],
      load: [],
      columns: [
        %{key: :name, label: "Наименование"},
        %{key: :bin, label: "БИН"},
        %{key: :phone, label: "Телефон"}
      ],
      fields: [
        %{name: :name, label: "Наименование", type: :text, required: true},
        %{name: :bin, label: "БИН", type: :text},
        %{name: :iin, label: "ИИН", type: :text},
        %{name: :address, label: "Адрес", type: :text},
        %{name: :phone, label: "Телефон", type: :text}
      ],
      row: fn record ->
        %{id: record.id, name: record.name, bin: record.bin, phone: record.phone}
      end
    }
  end

  # ---------------------------------------------------------------------------
  # Подразделения
  # ---------------------------------------------------------------------------

  defp department_spec do
    %{
      title: "Подразделения организаций",
      resource: Core.Department,
      tenant?: true,
      sort: [name: :asc],
      load: [],
      columns: [
        %{key: :name, label: "Наименование"},
        %{key: :code, label: "Код"}
      ],
      fields: [
        %{name: :name, label: "Наименование", type: :text, required: true},
        %{name: :code, label: "Код", type: :text}
      ],
      row: fn record -> %{id: record.id, name: record.name, code: record.code} end
    }
  end

  # ---------------------------------------------------------------------------
  # Контрагенты
  # ---------------------------------------------------------------------------

  defp counterparty_spec do
    %{
      title: "Контрагенты",
      resource: Catalog.Counterparty,
      tenant?: true,
      sort: [name: :asc],
      load: [],
      columns: [
        %{key: :name, label: "Наименование"},
        %{key: :kind, label: "Тип"},
        %{key: :bin, label: "БИН"},
        %{key: :phone, label: "Телефон"}
      ],
      fields: [
        %{name: :name, label: "Наименование", type: :text, required: true},
        %{name: :kind, label: "Тип", type: :select, options: @legal_kinds, required: true},
        %{name: :bin, label: "БИН", type: :text},
        %{name: :iin, label: "ИИН", type: :text},
        %{name: :phone, label: "Телефон", type: :text},
        %{name: :email, label: "E-mail", type: :text},
        %{name: :address, label: "Адрес", type: :text},
        %{name: :comment, label: "Комментарий", type: :textarea}
      ],
      row: fn record ->
        %{
          id: record.id,
          name: record.name,
          kind: label_for(@legal_kinds, record.kind),
          bin: record.bin,
          phone: record.phone
        }
      end
    }
  end

  # ---------------------------------------------------------------------------
  # Договоры контрагентов
  # ---------------------------------------------------------------------------

  defp contract_spec do
    %{
      title: "Договоры контрагентов",
      resource: Catalog.Contract,
      tenant?: true,
      sort: [number: :asc],
      load: [:counterparty, :currency],
      columns: [
        %{key: :number, label: "Номер"},
        %{key: :counterparty, label: "Контрагент"},
        %{key: :amount, label: "Сумма"},
        %{key: :valid_to, label: "Действует до"}
      ],
      fields: [
        %{name: :number, label: "Номер", type: :text, required: true},
        %{name: :name, label: "Наименование", type: :text},
        %{
          name: :counterparty_id,
          label: "Контрагент",
          type: :ref,
          required: true,
          resource: Catalog.Counterparty
        },
        %{name: :currency_id, label: "Валюта", type: :ref, resource: Catalog.Currency},
        %{name: :amount, label: "Сумма", type: :number},
        %{name: :valid_from, label: "Действует с", type: :date},
        %{name: :valid_to, label: "Действует по", type: :date}
      ],
      row: fn record ->
        %{
          id: record.id,
          number: record.number,
          counterparty: record.counterparty && record.counterparty.name,
          amount: format_decimal(record.amount),
          valid_to: format_date(record.valid_to)
        }
      end
    }
  end

  # ---------------------------------------------------------------------------
  # Номенклатура
  # ---------------------------------------------------------------------------

  defp nomenclature_spec do
    %{
      title: "Номенклатура",
      resource: Catalog.Nomenclature,
      tenant?: true,
      sort: [name: :asc],
      load: [:unit],
      columns: [
        %{key: :code, label: "Код"},
        %{key: :name, label: "Наименование"},
        %{key: :kind, label: "Вид"},
        %{key: :price, label: "Цена"}
      ],
      fields: [
        %{name: :code, label: "Код", type: :text},
        %{name: :name, label: "Наименование", type: :text, required: true},
        %{name: :kind, label: "Вид", type: :select, options: @nomenclature_kinds, required: true},
        %{name: :unit_id, label: "Единица измерения", type: :ref, resource: Catalog.Unit},
        %{name: :price, label: "Цена", type: :number},
        %{name: :vat_rate, label: "Ставка НДС", type: :select, options: @vat_rates},
        %{name: :comment, label: "Комментарий", type: :textarea}
      ],
      row: fn record ->
        %{
          id: record.id,
          code: record.code,
          name: record.name,
          kind: label_for(@nomenclature_kinds, record.kind),
          price: format_decimal(record.price)
        }
      end
    }
  end

  # ---------------------------------------------------------------------------
  # Склады
  # ---------------------------------------------------------------------------

  defp warehouse_spec do
    %{
      title: "Склады (места хранения)",
      resource: Catalog.Warehouse,
      tenant?: true,
      sort: [name: :asc],
      load: [],
      columns: [
        %{key: :code, label: "Код"},
        %{key: :name, label: "Наименование"},
        %{key: :address, label: "Адрес"}
      ],
      fields: [
        %{name: :code, label: "Код", type: :text},
        %{name: :name, label: "Наименование", type: :text, required: true},
        %{name: :address, label: "Адрес", type: :text},
        %{name: :comment, label: "Комментарий", type: :textarea}
      ],
      row: fn record ->
        %{id: record.id, code: record.code, name: record.name, address: record.address}
      end
    }
  end

  # ---------------------------------------------------------------------------
  # Единицы измерения
  # ---------------------------------------------------------------------------

  defp unit_spec do
    %{
      title: "Классификатор единиц измерения",
      resource: Catalog.Unit,
      tenant?: true,
      sort: [code: :asc],
      load: [],
      columns: [
        %{key: :code, label: "Код"},
        %{key: :name, label: "Наименование"},
        %{key: :designation, label: "Условное обозначение"}
      ],
      fields: [
        %{name: :code, label: "Код", type: :text, required: true},
        %{name: :name, label: "Наименование", type: :text, required: true},
        %{name: :designation, label: "Условное обозначение", type: :text}
      ],
      row: fn record ->
        %{
          id: record.id,
          code: record.code,
          name: record.name,
          designation: record.designation
        }
      end
    }
  end

  # ---------------------------------------------------------------------------
  # Валюты
  # ---------------------------------------------------------------------------

  defp currency_spec do
    %{
      title: "Валюты",
      resource: Catalog.Currency,
      tenant?: true,
      sort: [code: :asc],
      load: [],
      columns: [
        %{key: :code, label: "Код"},
        %{key: :name, label: "Наименование"},
        %{key: :rate, label: "Курс"},
        %{key: :base, label: "Базовая"}
      ],
      fields: [
        %{name: :code, label: "Код ISO 4217", type: :text, required: true},
        %{name: :name, label: "Наименование", type: :text, required: true},
        %{name: :rate, label: "Курс", type: :number, required: true},
        %{name: :rate_date, label: "Дата курса", type: :date},
        %{name: :base, label: "Базовая валюта", type: :select, options: @yes_no}
      ],
      row: fn record ->
        %{
          id: record.id,
          code: record.code,
          name: record.name,
          rate: format_decimal(record.rate),
          base: if(record.base, do: "Да", else: "Нет")
        }
      end
    }
  end

  # ---------------------------------------------------------------------------
  # Банки
  # ---------------------------------------------------------------------------

  defp bank_spec do
    %{
      title: "Банки",
      resource: Catalog.Bank,
      tenant?: true,
      sort: [name: :asc],
      load: [],
      columns: [
        %{key: :bic, label: "БИК"},
        %{key: :name, label: "Наименование"},
        %{key: :address, label: "Адрес"}
      ],
      fields: [
        %{name: :bic, label: "БИК", type: :text, required: true},
        %{name: :name, label: "Краткое наименование", type: :text, required: true},
        %{name: :bank_name, label: "Полное наименование", type: :text},
        %{name: :mfo, label: "МФО", type: :text},
        %{name: :address, label: "Адрес", type: :text}
      ],
      row: fn record ->
        %{id: record.id, bic: record.bic, name: record.name, address: record.address}
      end
    }
  end

  # ---------------------------------------------------------------------------
  # Деньги: статьи, счета и кассы
  # ---------------------------------------------------------------------------

  defp cash_flow_item_spec do
    %{
      title: "Статьи движения денежных средств",
      resource: Pulse.Treasury.CashFlowItem,
      tenant?: true,
      sort: [name: :asc],
      load: [],
      columns: [
        %{key: :code, label: "Код"},
        %{key: :name, label: "Наименование"},
        %{key: :kind, label: "Вид"}
      ],
      fields: [
        %{name: :code, label: "Код", type: :text},
        %{name: :name, label: "Наименование", type: :text, required: true},
        %{
          name: :kind,
          label: "Вид движения",
          type: :select,
          options: @cash_flow_kinds,
          required: true
        },
        %{name: :account_code, label: "Счёт учёта", type: :text},
        %{name: :comment, label: "Комментарий", type: :textarea}
      ],
      row: fn record ->
        %{
          id: record.id,
          code: record.code,
          name: record.name,
          kind: label_for(@cash_flow_kinds, record.kind)
        }
      end
    }
  end

  defp bank_account_spec do
    %{
      title: "Банковские счета",
      resource: Pulse.Treasury.BankAccount,
      tenant?: true,
      sort: [name: :asc],
      load: [:bank],
      columns: [
        %{key: :account_number, label: "Номер счёта"},
        %{key: :name, label: "Наименование"},
        %{key: :bank, label: "Банк"}
      ],
      fields: [
        %{name: :name, label: "Наименование", type: :text, required: true},
        %{name: :account_number, label: "Номер счёта", type: :text, required: true},
        %{name: :bank_id, label: "Банк", type: :ref, resource: Pulse.Catalog.Bank},
        %{name: :currency_id, label: "Валюта", type: :ref, resource: Pulse.Catalog.Currency},
        %{name: :comment, label: "Комментарий", type: :textarea}
      ],
      row: fn record ->
        %{
          id: record.id,
          account_number: record.account_number,
          name: record.name,
          bank: bank_name(record)
        }
      end
    }
  end

  defp cash_desk_spec do
    %{
      title: "Кассы",
      resource: Pulse.Treasury.CashDesk,
      tenant?: true,
      sort: [name: :asc],
      load: [],
      columns: [
        %{key: :code, label: "Код"},
        %{key: :name, label: "Наименование"}
      ],
      fields: [
        %{name: :name, label: "Наименование", type: :text, required: true},
        %{name: :code, label: "Код", type: :text},
        %{name: :currency_id, label: "Валюта", type: :ref, resource: Pulse.Catalog.Currency},
        %{name: :comment, label: "Комментарий", type: :textarea}
      ],
      row: fn record ->
        %{id: record.id, code: record.code, name: record.name}
      end
    }
  end

  defp bank_name(%{bank: %Ash.NotLoaded{}}), do: nil
  defp bank_name(%{bank: nil}), do: nil
  defp bank_name(%{bank: bank}), do: bank.name

  # ---------------------------------------------------------------------------
  # План счетов и субконто
  # ---------------------------------------------------------------------------

  defp account_spec do
    %{
      title: "План счетов бухгалтерского учета",
      resource: Pulse.Accounting.Account,
      tenant?: false,
      sort: [code: :asc],
      load: [],
      columns: [
        %{key: :code, label: "Код"},
        %{key: :name, label: "Наименование"},
        %{key: :kind, label: "Вид"},
        %{key: :off_balance, label: "Забалансовый"}
      ],
      fields: [
        %{name: :code, label: "Код", type: :text, required: true},
        %{name: :name, label: "Наименование", type: :text, required: true},
        %{name: :kind, label: "Вид счёта", type: :select, options: @account_kinds},
        %{name: :off_balance, label: "Забалансовый", type: :select, options: @yes_no},
        %{name: :currency, label: "Валютный учёт", type: :select, options: @yes_no},
        %{name: :quantity, label: "Количественный учёт", type: :select, options: @yes_no},
        %{name: :parent_code, label: "Код счёта-родителя", type: :text}
      ],
      row: fn record ->
        %{
          id: record.id,
          code: record.code,
          name: record.name,
          kind: label_for(@account_kinds, record.kind),
          off_balance: if(record.off_balance, do: "Да", else: "Нет")
        }
      end
    }
  end

  defp subaccount_type_spec do
    %{
      title: "Виды субконто",
      resource: Pulse.Accounting.SubaccountType,
      tenant?: false,
      sort: [code: :asc],
      load: [],
      columns: [
        %{key: :code, label: "Код"},
        %{key: :name, label: "Наименование"},
        %{key: :reference, label: "Справочник"}
      ],
      fields: [
        %{name: :code, label: "Код", type: :text, required: true},
        %{name: :name, label: "Наименование", type: :text, required: true},
        %{name: :reference, label: "Справочник", type: :text}
      ],
      row: fn record ->
        %{id: record.id, code: record.code, name: record.name, reference: record.reference}
      end
    }
  end

  defp entry_template_spec do
    %{
      title: "Типовые операции",
      resource: Pulse.Accounting.EntryTemplate,
      tenant?: false,
      sort: [kind: :asc],
      load: [],
      columns: [
        %{key: :kind, label: "Операция"},
        %{key: :debit_account_code, label: "Дебет"},
        %{key: :credit_account_code, label: "Кредит"}
      ],
      fields: [
        %{
          name: :kind,
          label: "Операция",
          type: :select,
          options: @template_kinds,
          required: true
        },
        %{name: :name, label: "Наименование", type: :text, required: true},
        %{name: :debit_account_code, label: "Счёт дебета", type: :text, required: true},
        %{name: :credit_account_code, label: "Счёт кредита", type: :text, required: true},
        %{name: :note, label: "Примечание", type: :textarea}
      ],
      row: fn record ->
        %{
          id: record.id,
          kind: label_for(@template_kinds, record.kind),
          debit_account_code: record.debit_account_code,
          credit_account_code: record.credit_account_code
        }
      end
    }
  end

  # ---------------------------------------------------------------------------
  # Кадровый учёт (этап 8)
  # ---------------------------------------------------------------------------

  defp person_spec do
    %{
      title: "Физические лица",
      resource: Pulse.HR.Person,
      tenant?: true,
      sort: [last_name: :asc, first_name: :asc],
      load: [],
      columns: [
        %{key: :last_name, label: "Фамилия"},
        %{key: :first_name, label: "Имя"},
        %{key: :middle_name, label: "Отчество"},
        %{key: :iin, label: "ИИН"}
      ],
      fields: [
        %{name: :last_name, label: "Фамилия", type: :text, required: true},
        %{name: :first_name, label: "Имя", type: :text, required: true},
        %{name: :middle_name, label: "Отчество", type: :text},
        %{name: :iin, label: "ИИН", type: :text},
        %{name: :birth_date, label: "Дата рождения", type: :date},
        %{name: :identity_document, label: "Удостоверяющий документ", type: :text},
        %{name: :address, label: "Адрес", type: :text},
        %{name: :phone, label: "Телефон", type: :text}
      ],
      row: fn record ->
        %{
          id: record.id,
          last_name: record.last_name,
          first_name: record.first_name,
          middle_name: record.middle_name,
          # ИИН расшифровывается типом поля: в базе он зашифрован.
          iin: record.iin
        }
      end
    }
  end

  defp position_spec do
    %{
      title: "Должности организаций",
      resource: Pulse.HR.Position,
      tenant?: true,
      sort: [name: :asc],
      load: [],
      columns: [
        %{key: :code, label: "Код"},
        %{key: :name, label: "Наименование"},
        %{key: :salary, label: "Оклад", align: :right}
      ],
      fields: [
        %{name: :code, label: "Код", type: :text},
        %{name: :name, label: "Наименование", type: :text, required: true},
        %{name: :salary, label: "Оклад", type: :number}
      ],
      row: fn record ->
        %{
          id: record.id,
          code: record.code,
          name: record.name,
          salary: format_decimal(record.salary)
        }
      end
    }
  end

  defp employee_spec do
    %{
      title: "Сотрудники",
      resource: Pulse.HR.Employee,
      tenant?: true,
      sort: [inserted_at: :desc],
      load: [:person, :position, :department],
      columns: [
        %{key: :person, label: "Физлицо"},
        %{key: :position, label: "Должность"},
        %{key: :hire_date, label: "Принят"},
        %{key: :salary, label: "Оклад", align: :right},
        %{key: :status, label: "Состояние"}
      ],
      fields: [
        %{
          name: :person_id,
          label: "Физлицо",
          type: :ref,
          required: true,
          resource: Pulse.HR.Person
        },
        %{name: :position_id, label: "Должность", type: :ref, resource: Pulse.HR.Position},
        %{
          name: :department_id,
          label: "Подразделение",
          type: :ref,
          resource: Core.Department
        },
        %{name: :hire_date, label: "Дата приёма", type: :date},
        %{name: :salary, label: "Оклад", type: :number},
        %{
          name: :status,
          label: "Состояние",
          type: :select,
          options: [{"Работает", :working}, {"Уволен", :dismissed}]
        },
        %{name: :bank_account, label: "Счёт для выплаты", type: :text}
      ],
      row: fn record ->
        %{
          id: record.id,
          person: employee_name(record.person),
          position: employee_name(record.position),
          hire_date: format_date(record.hire_date),
          salary: format_decimal(record.salary),
          status: employee_status(record.status)
        }
      end
    }
  end

  defp employee_name(nil), do: "—"
  defp employee_name(%Ash.NotLoaded{}), do: "—"
  defp employee_name(%Pulse.HR.Person{} = person), do: Pulse.HR.Person.full_name(person)
  defp employee_name(%{name: name}), do: name

  defp employee_status(:working), do: "Работает"
  defp employee_status(:dismissed), do: "Уволен"
  defp employee_status(status), do: to_string(status)

  # ---------------------------------------------------------------------------
  # Законодательные параметры (этап 7)
  # ---------------------------------------------------------------------------

  defp statutory_rate_spec do
    %{
      title: "Сведения о ставках налогов, сборов и отчислений",
      resource: Pulse.Tax.StatutoryRate,
      tenant?: false,
      sort: [code: :asc, valid_from: :desc],
      load: [],
      columns: [
        %{key: :code, label: "Код"},
        %{key: :name, label: "Наименование"},
        %{key: :value, label: "Значение", align: :right},
        %{key: :valid_from, label: "Действует с"},
        %{key: :valid_to, label: "Действует по"}
      ],
      fields: [
        %{
          name: :code,
          label: "Код параметра",
          type: :select,
          options: Enum.map(Pulse.Tax.StatutoryRate.known_codes(), &{&1, &1}),
          required: true
        },
        %{name: :name, label: "Наименование", type: :text},
        %{name: :value, label: "Значение", type: :number, required: true},
        %{name: :valid_from, label: "Действует с", type: :date, required: true},
        %{name: :valid_to, label: "Действует по", type: :date},
        %{name: :note, label: "Примечание", type: :textarea}
      ],
      row: fn record ->
        %{
          id: record.id,
          code: record.code,
          name: record.name,
          value: format_decimal(record.value),
          valid_from: format_date(record.valid_from),
          valid_to: format_date(record.valid_to)
        }
      end
    }
  end

  defp vat_rate_spec do
    %{
      title: "Ставки НДС",
      resource: Pulse.Tax.StatutoryRate,
      tenant?: false,
      sort: [code: :asc, valid_from: :desc],
      load: [],
      base_filter: [code: "vat_rate"],
      columns: [
        %{key: :code, label: "Код"},
        %{key: :name, label: "Наименование"},
        %{key: :value, label: "Ставка, %", align: :right},
        %{key: :valid_from, label: "Действует с"},
        %{key: :valid_to, label: "Действует по"}
      ],
      fields: [
        %{
          name: :code,
          label: "Код параметра",
          type: :select,
          options: [{"vat_rate", "vat_rate"}, {"vat_rate_reduced", "vat_rate_reduced"}],
          required: true
        },
        %{name: :name, label: "Наименование", type: :text},
        %{name: :value, label: "Ставка, %", type: :number, required: true},
        %{name: :valid_from, label: "Действует с", type: :date, required: true},
        %{name: :valid_to, label: "Действует по", type: :date},
        %{name: :note, label: "Примечание", type: :textarea}
      ],
      row: fn record ->
        %{
          id: record.id,
          code: record.code,
          name: record.name,
          value: format_decimal(record.value),
          valid_from: format_date(record.valid_from),
          valid_to: format_date(record.valid_to)
        }
      end
    }
  end

  defp label_for(options, value) do
    Enum.find_value(options, to_string(value), fn {label, option_value} ->
      if option_value == value, do: label
    end)
  end

  defp format_decimal(nil), do: nil

  defp format_decimal(value) do
    value
    |> Decimal.round(2)
    |> Decimal.to_string()
  end

  defp format_date(nil), do: nil
  defp format_date(%Date{} = date), do: Date.to_string(date)
end
