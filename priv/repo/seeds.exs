# Скрипт наполнения базы. Запускается командой `mix ash.setup` или
# автоматически при старте контейнера web.
#
# Этап 2: первый администратор, организации с членствами, матрица прав
# по умолчанию (`Pulse.Core.Roles.default_matrix/0`) и демо-данные
# справочников.
# Этап 3: сквозной сценарий «поступление → остаток → реализация».
# Этап 7: законодательные параметры (`statutory_rates`) и счета-фактуры,
# сформированные по проведённым документам сквозного сценария.
# Этап 8: кадры (должности, физлица, сотрудники) и проведённое начисление
# заработной платы за октябрь.
#
# Скрипт идемпотентен: при повторном запуске только достраивает недостающее.

require Logger
require Ash.Query

admin_email = System.get_env("ADMIN_EMAIL", "admin@qinalma.local")
admin_password = System.get_env("ADMIN_PASSWORD", "admin12345678")

read_all = fn resource, opts ->
  case Ash.read(resource, Keyword.put(opts, :authorize?, false)) do
    {:ok, rows} ->
      rows

    {:error, error} ->
      Logger.error("Не удалось прочитать #{inspect(resource)}: #{inspect(error)}")
      []
  end
end

# Чтение с фильтром (список условий вида `[code: "KZT"]`).
read_by = fn resource, filter, opts ->
  query = Ash.Query.filter(resource, ^filter)

  case Ash.read(query, Keyword.put(opts, :authorize?, false)) do
    {:ok, rows} ->
      rows

    {:error, error} ->
      Logger.error("Не удалось прочитать #{inspect(resource)}: #{inspect(error)}")
      []
  end
end

# Создание записи. Опции: `:action`, `:tenant`, `:domain`.
create = fn resource, attrs, opts ->
  action = Keyword.get(opts, :action, :create)
  tenant = Keyword.get(opts, :tenant)

  changeset =
    resource
    |> Ash.Changeset.for_create(action, attrs)
    |> then(fn changeset ->
      if tenant, do: Ash.Changeset.set_tenant(changeset, tenant), else: changeset
    end)

  Ash.create(
    changeset,
    Keyword.merge([authorize?: false], Keyword.drop(opts, [:action, :tenant]))
  )
end

log_error = fn message, error ->
  Logger.error("#{message}: #{inspect(error)}")
end

# Документ со строками — для проведения нужны загруженные строки.
reload = fn resource, id, tenant ->
  query = Ash.Query.filter(resource, id == ^id)

  case Ash.read(query, tenant: tenant, authorize?: false, load: [:lines]) do
    {:ok, [document]} -> document
    _ -> nil
  end
end

# Строка табличной части документа.
add_line = fn resource, document, line_no, nomenclature_id, quantity, price, tenant ->
  quantity = Decimal.new(quantity)
  price = Decimal.new(price)

  resource
  |> Ash.Changeset.for_create(:create, %{
    organization_id: tenant,
    document_id: document.id,
    line_no: line_no,
    nomenclature_id: nomenclature_id,
    quantity: quantity,
    price: price,
    amount: Decimal.mult(quantity, price)
  })
  |> Ash.Changeset.set_tenant(tenant)
  |> Ash.create(authorize?: false)
end

# Оплата от покупателя: закрывает часть долга и создаёт остаток на счёте,
# чтобы виджеты начальной страницы показывали настоящие цифры.
seed_payment = fn actor, tenant, counterparty ->
  account = read_all.(Pulse.Treasury.BankAccount, tenant: tenant) |> List.first()
  item = read_by.(Pulse.Treasury.CashFlowItem, [code: "IN-SALE"], tenant: tenant) |> List.first()

  if account do
    attrs = %{
      doc_date: ~D[2026-10-15],
      number: "Б-000001",
      direction: :receipt,
      bank_account_id: account.id,
      counterparty_id: counterparty.id,
      cash_flow_item_id: item && item.id,
      amount: Decimal.new("1000000")
    }

    case create.(Pulse.Treasury.BankDocument, attrs, tenant: tenant) do
      {:ok, document} ->
        case Pulse.Accounting.Posting.post(document, actor, Pulse.Posting.TreasuryPayment) do
          {:ok, _posted} -> Logger.info("Создано и проведено поступление Б-000001")
          {:error, error} -> log_error.("Не провелось поступление денег", error)
        end

      {:error, error} ->
        log_error.("Не создался банковский документ", error)
    end
  end
end

# Реализация части поступившего товара: сквозной сценарий замыкается.
seed_shipment = fn actor, tenant, warehouse, counterparty, goods, currency ->
  attrs = %{
    doc_date: ~D[2026-10-12],
    number: "Р-000001",
    counterparty_id: counterparty.id,
    warehouse_id: warehouse.id,
    currency_id: currency && currency.id
  }

  with {:ok, shipment} <- create.(Pulse.Sales.Shipment, attrs, tenant: tenant) do
    goods
    |> Enum.with_index(1)
    |> Enum.each(fn {good, index} ->
      _ =
        add_line.(
          Pulse.Sales.ShipmentLine,
          shipment,
          index,
          good.id,
          "4",
          Decimal.add(good.price || Decimal.new("1000"), Decimal.new("500")),
          tenant
        )
    end)

    shipment = reload.(Pulse.Sales.Shipment, shipment.id, tenant)

    case Pulse.Accounting.Posting.post(shipment, actor, Pulse.Posting.SalesShipment) do
      {:ok, posted} ->
        Logger.info("Создано и проведено реализация Р-000001")
        seed_payment.(actor, tenant, counterparty)

      {:error, error} ->
        log_error.("Не провелась реализация", error)
    end
  end
end

# --- 1. Пользователи -------------------------------------------------------
# Администратор создаётся, только если его ещё нет. Если прочитать список
# не удалось, создавать не пробуем: иначе повторный запуск упадёт на
# уникальности email вместо понятного сообщения.

users =
  case Ash.read(Pulse.Accounts.User, domain: Pulse.Accounts, authorize?: false) do
    {:ok, users} ->
      users

    {:error, error} ->
      Logger.error(
        "Не удалось прочитать пользователей, администратор не создаётся: #{inspect(error)}"
      )

      :unreadable
  end

admin =
  case users do
    :unreadable ->
      nil

    users ->
      Enum.find(users, &(to_string(&1.email) == admin_email)) ||
        case create.(
               Pulse.Accounts.User,
               %{
                 email: admin_email,
                 password: admin_password,
                 password_confirmation: admin_password
               },
               action: :register_with_password,
               domain: Pulse.Accounts
             ) do
          {:ok, user} ->
            Logger.info("Создан первый администратор: #{user.email}")
            user

          {:error, error} ->
            log_error.("Не удалось создать администратора", error)
            nil
        end
  end

# --- 2. Матрица прав -------------------------------------------------------

permissions = read_all.(Pulse.Core.RolePermission, [])

if permissions == [] do
  now = DateTime.utc_now()

  rows =
    for {role, resource, action} <- Pulse.Core.Roles.default_matrix() do
      %{
        role: role,
        resource: resource,
        action: action,
        allowed?: true,
        inserted_at: now,
        updated_at: now
      }
    end

  {count, _} = Pulse.Repo.insert_all("role_permissions", rows)
  Pulse.Core.Permissions.reload()
  Logger.info("Загружена матрица прав по умолчанию: #{count} строк")
else
  Logger.info("Матрица прав уже загружена (#{length(permissions)} строк)")
end

# --- 2a. План счетов, субконто и шаблоны проводок -------------------------
# Законодательный справочник, общий для всех организаций. Загружается
# кодом (`Pulse.Accounting.ChartOfAccounts`), правится через интерфейс.
# Наполнение добавляющее: новые счета и шаблоны доезжают до уже
# поднятой базы, а существующие правки не затираются.

alias Pulse.Accounting.ChartOfAccounts

existing_subaccounts =
  read_all.(Pulse.Accounting.SubaccountType, []) |> Enum.map(& &1.code)

Enum.each(ChartOfAccounts.subaccount_types(), fn attrs ->
  if attrs.code in existing_subaccounts do
    :ok
  else
    case create.(Pulse.Accounting.SubaccountType, attrs, []) do
      {:ok, _record} -> :ok
      {:error, error} -> log_error.("Не создался вид субконто #{attrs.code}", error)
    end
  end
end)

existing_accounts = read_all.(Pulse.Accounting.Account, []) |> Enum.map(& &1.code)

Enum.each(ChartOfAccounts.accounts(), fn attrs ->
  if attrs.code in existing_accounts do
    :ok
  else
    attrs = Map.put_new(attrs, :subaccount_codes, [])

    case create.(Pulse.Accounting.Account, attrs, []) do
      {:ok, _record} -> :ok
      {:error, error} -> log_error.("Не создался счёт #{attrs.code}", error)
    end
  end
end)

existing_templates =
  read_all.(Pulse.Accounting.EntryTemplate, []) |> Enum.map(& &1.kind)

Enum.each(ChartOfAccounts.templates(), fn attrs ->
  if attrs.kind in existing_templates do
    :ok
  else
    case create.(Pulse.Accounting.EntryTemplate, attrs, []) do
      {:ok, _record} -> :ok
      {:error, error} -> log_error.("Не создался шаблон #{attrs.kind}", error)
    end
  end
end)

Logger.info("План счетов РК сверен: #{length(ChartOfAccounts.accounts())} счетов")

# --- 2b. Законодательные параметры (этап 7) --------------------------------
# Ставки и пороги не зашиты в код: значения лежат в `statutory_rates`
# с датами действия и правятся через интерфейс без релиза. Значения по
# умолчанию — ориентир, а не проверенная истина: их нужно сверить
# с действующей редакцией Налогового кодекса и перепроверить с бухгалтером.

if read_all.(Pulse.Tax.StatutoryRate, []) == [] do
  Enum.each(Pulse.Tax.StatutoryRates.defaults(), fn attrs ->
    case create.(Pulse.Tax.StatutoryRate, attrs, []) do
      {:ok, _record} -> :ok
      {:error, error} -> log_error.("Не создался параметр #{attrs.code}", error)
    end
  end)

  Logger.info(
    "Загружены законодательные параметры: #{length(Pulse.Tax.StatutoryRates.defaults())} значений"
  )
else
  Logger.info("Законодательные параметры уже загружены")
end

# --- 3. Организации --------------------------------------------------------

organizations = read_all.(Pulse.Core.Organization, [])

organizations =
  if organizations == [] do
    demo = [
      %{
        name: "ТОО «Киналма»",
        bin: "190140012345",
        address: "г. Алматы, пр. Абая, 44",
        phone: "+7 (727) 350-11-22"
      },
      %{
        name: "ИП МАРШ",
        bin: "040940012067",
        address: "г. Алматы, ул. Кунаева, 12",
        phone: "+7 (727) 293-45-90"
      }
    ]

    Enum.reduce(demo, [], fn attrs, acc ->
      case create.(Pulse.Core.Organization, attrs, []) do
        {:ok, organization} ->
          acc ++ [organization]

        {:error, error} ->
          log_error.("Не создалась организация #{attrs.name}", error)
          acc
      end
    end)
  else
    organizations
  end

# --- 4. Членства -----------------------------------------------------------

memberships = read_all.(Pulse.Core.OrganizationMembership, [])

memberships =
  if admin do
    Enum.reduce(organizations, memberships, fn organization, acc ->
      exists? =
        Enum.any?(acc, &(&1.user_id == admin.id and &1.organization_id == organization.id))

      if exists? do
        acc
      else
        attrs = %{user_id: admin.id, organization_id: organization.id, role: "admin"}

        case create.(Pulse.Core.OrganizationMembership, attrs, []) do
          {:ok, membership} ->
            acc ++ [membership]

          {:error, error} ->
            log_error.("Не создалось членство", error)
            acc
        end
      end
    end)
  else
    memberships
  end

# Активная организация в рабочей области администратора.
if admin && organizations != [] do
  workspace = Pulse.Accounts.load_or_create_workspace(admin)
  first_organization = List.first(organizations)

  unless workspace.active_organization_id do
    _ =
      Pulse.Accounts.save_workspace(workspace, admin, %{
        active_organization_id: first_organization.id
      })
  end
end

# --- 5. Демо-данные справочников ------------------------------------------
# Наполняются для первой организации; остальные остаются пустыми,
# чтобы в интерфейсе была видна изоляция данных по организациям.

primary = List.first(organizations)

if primary && admin do
  tenant = primary.id

  seed_each = fn resource, rows, build ->
    if read_all.(resource, tenant: tenant) == [] do
      Enum.each(rows, fn attrs ->
        case create.(resource, build.(attrs), tenant: tenant) do
          {:ok, _record} -> :ok
          {:error, error} -> log_error.("Не создалась запись #{inspect(attrs)}", error)
        end
      end)
    end
  end

  # Единицы измерения
  seed_each.(
    Pulse.Catalog.Unit,
    [
      %{code: "ШТ", name: "Штука", designation: "шт"},
      %{code: "КГ", name: "Килограмм", designation: "кг"},
      %{code: "Л", name: "Литр", designation: "л"},
      %{code: "М2", name: "Квадратный метр", designation: "м²"},
      %{code: "УПАК", name: "Упаковка", designation: "упак"}
    ],
    & &1
  )

  # Валюты
  seed_each.(
    Pulse.Catalog.Currency,
    [
      %{code: "KZT", name: "Казахстанский тенге", rate: "1", base: true},
      %{code: "USD", name: "Доллар США", rate: "521.35"},
      %{code: "EUR", name: "Евро", rate: "566.10"},
      %{code: "RUB", name: "Российский рубль", rate: "5.42"}
    ],
    &Map.put(&1, :rate_date, ~D[2026-10-20])
  )

  # Банки
  seed_each.(
    Pulse.Catalog.Bank,
    [
      %{bic: "000345000011", name: "Халык Банк", bank_name: "АО «Халык Банк»", mfo: "KKIS921K"},
      %{
        bic: "000345000022",
        name: "ЦентрКредит",
        bank_name: "АО «Банк ЦентрКредит»",
        mfo: "KKIS921A"
      },
      %{bic: "000345000033", name: "ForteBank", bank_name: "АО «ForteBank»", mfo: "KKIS921F"}
    ],
    & &1
  )

  # Контрагенты
  seed_each.(
    Pulse.Catalog.Counterparty,
    [
      %{
        name: "ТОО «Алатау Ритейл»",
        kind: :legal,
        bin: "120140012345",
        address: "г. Алматы, ул. Розыбакиева, 155",
        phone: "+7 (727) 311-00-11"
      },
      %{
        name: "ТОО «ТехноПром Казахстан»",
        kind: :legal,
        bin: "160540011122",
        address: "г. Алматы, ул. Ауэзова, 77",
        phone: "+7 (727) 312-22-33"
      },
      %{
        name: "ТОО «КазЭлектро»",
        kind: :legal,
        bin: "130240014455",
        address: "г. Караганда, бул. Мира, 21",
        phone: "+7 (7212) 44-55-66"
      },
      %{
        name: "ТОО «Степь Логистик»",
        kind: :legal,
        bin: "150640017788",
        address: "г. Шымкент, пр. Тауке хана, 5",
        phone: "+7 (7252) 77-88-99"
      },
      %{
        name: "ИП «Светлова О.И.»",
        kind: :individual,
        iin: "900101501234",
        phone: "+7 (701) 234-56-78"
      },
      %{
        name: "ИП «Омаров Б.Т.»",
        kind: :individual,
        iin: "850712300456",
        phone: "+7 (702) 876-54-32"
      }
    ],
    & &1
  )

  # Склады
  seed_each.(
    Pulse.Catalog.Warehouse,
    [
      %{code: "WH-01", name: "Основной склад", address: "г. Алматы, ул. Ауэзова, 77"},
      %{code: "WH-02", name: "Городской склад", address: "г. Алматы, пр. Абая, 44"}
    ],
    & &1
  )

  # Статьи движения денежных средств
  seed_each.(
    Pulse.Treasury.CashFlowItem,
    [
      %{code: "IN-SALE", name: "Оплата от покупателей", kind: :receipt, account_code: "1210"},
      %{code: "IN-OTHER", name: "Прочие поступления", kind: :receipt, account_code: "6280"},
      %{code: "OUT-SUP", name: "Оплата поставщикам", kind: :expense, account_code: "3310"},
      %{code: "OUT-SAL", name: "Выплата заработной платы", kind: :expense, account_code: "3350"}
    ],
    & &1
  )

  # Банковские счета
  seed_each.(
    Pulse.Treasury.BankAccount,
    [
      %{name: "Основной счёт", account_number: "KZ126010111000123456", bank_id: nil},
      %{name: "Валютный счёт", account_number: "KZ126010111000654321", bank_id: nil}
    ],
    & &1
  )

  # Кассы
  seed_each.(
    Pulse.Treasury.CashDesk,
    [
      %{code: "CASH-01", name: "Касса организации"},
      %{code: "CASH-02", name: "Операционная касса"}
    ],
    & &1
  )

  # Подразделения
  seed_each.(
    Pulse.Core.Department,
    [
      %{code: "ACC", name: "Бухгалтерия"},
      %{code: "SALES", name: "Отдел продаж"},
      %{code: "WH", name: "Складское подразделение"}
    ],
    & &1
  )

  # Номенклатура (ссылка на единицу измерения, если она есть)
  unit =
    Pulse.Catalog.Unit
    |> read_all.(tenant: tenant)
    |> List.first()

  seed_each.(
    Pulse.Catalog.Nomenclature,
    [
      %{
        code: "N-0001",
        name: "Ноутбук ASUS ZenBook 14",
        kind: :product,
        price: "385000",
        vat_rate: :twelve
      },
      %{
        code: "N-0002",
        name: "Монитор 27\" LG UltraGear",
        kind: :product,
        price: "125000",
        vat_rate: :twelve
      },
      %{
        code: "N-0003",
        name: "МФУ лазерное HP LaserJet",
        kind: :product,
        price: "98000",
        vat_rate: :twelve
      },
      %{
        code: "N-0004",
        name: "Клавиатура Logitech MX",
        kind: :product,
        price: "32000",
        vat_rate: :twelve
      },
      %{
        code: "N-0005",
        name: "Услуга настройки рабочего места",
        kind: :service,
        price: "15000",
        vat_rate: :twelve
      }
    ],
    fn attrs ->
      if unit, do: Map.put(attrs, :unit_id, unit.id), else: attrs
    end
  )

  # Договоры контрагентов
  counterparties = read_all.(Pulse.Catalog.Counterparty, tenant: tenant)

  currency = read_by.(Pulse.Catalog.Currency, [code: "KZT"], tenant: tenant) |> List.first()

  contracts = [
    %{number: "Д-001/26", name: "Поставка оборудования", amount: "4500000"},
    %{number: "Д-002/26", name: "Оказание логистических услуг", amount: "1250000"},
    %{number: "Д-003/26", name: "Сопровождение ИТ-инфраструктуры", amount: "980000"}
  ]

  seed_each.(
    Pulse.Catalog.Contract,
    contracts,
    fn attrs ->
      index = Enum.find_index(contracts, &(&1.number == attrs.number)) || 0

      attrs =
        case Enum.at(counterparties, index) do
          nil -> attrs
          counterparty -> Map.put(attrs, :counterparty_id, counterparty.id)
        end

      attrs = if currency, do: Map.put(attrs, :currency_id, currency.id), else: attrs

      attrs
      |> Map.put(:valid_from, ~D[2026-01-01])
      |> Map.put(:valid_to, ~D[2026-12-31])
    end
  )

  Logger.info("Демо-данные справочников готовы для организации «#{primary.name}»")

  # --- 6. Сквозной сценарий этапа 3: поступление → реализация --------------
  # Документы проводятся настоящим проведением, поэтому остатки в базе
  # сразу сходятся: 10 единиц товара пришли, 4 ушли на реализацию.

  if read_all.(Pulse.Purchasing.Receipt, tenant: tenant) == [] do
    warehouse = read_all.(Pulse.Catalog.Warehouse, tenant: tenant) |> List.first()
    counterparty = List.first(counterparties)
    goods = read_all.(Pulse.Catalog.Nomenclature, tenant: tenant) |> Enum.take(3)
    actor = Pulse.Core.Actor.build(admin, memberships, tenant)

    receipt_attrs = %{
      doc_date: ~D[2026-10-05],
      number: "П-000001",
      counterparty_id: counterparty && counterparty.id,
      warehouse_id: warehouse && warehouse.id,
      currency_id: currency && currency.id
    }

    with true <- warehouse && counterparty && goods != [],
         {:ok, receipt} <- create.(Pulse.Purchasing.Receipt, receipt_attrs, tenant: tenant) do
      goods
      |> Enum.with_index(1)
      |> Enum.each(fn {good, index} ->
        _ =
          add_line.(
            Pulse.Purchasing.ReceiptLine,
            receipt,
            index,
            good.id,
            "10",
            good.price || "1000",
            tenant
          )
      end)

      receipt = reload.(Pulse.Purchasing.Receipt, receipt.id, tenant)

      case Pulse.Accounting.Posting.post(receipt, actor, Pulse.Posting.PurchasingReceipt) do
        {:ok, _posted} ->
          Logger.info("Создано и проведено поступление П-000001")
          seed_shipment.(actor, tenant, warehouse, counterparty, goods, currency)

        {:error, error} ->
          log_error.("Не провелось поступление", error)
      end
    else
      _ -> Logger.info("Данных для сквозного сценария недостаточно")
    end
  end
else
  Logger.info("Организации не созданы — демо-данные справочников пропущены")
end

# --- 7. Периоды: закрываем сентябрь, чтобы демонстрировать запрет ---
# Октябрь остаётся открытым: в нём идут документы сквозного сценария.

if admin && primary do
  tenant = primary.id

  if Pulse.Accounting.Periods.closed_periods(tenant) == [] do
    case Pulse.Accounting.Periods.close_month(
           ~D[2026-09-01],
           tenant,
           Pulse.Core.Actor.build(admin, memberships, tenant)
         ) do
      {:ok, %{period: period}} ->
        Logger.info("Закрыт период #{Pulse.Accounting.Periods.month_label(period)}")

      {:error, error} ->
        log_error.("Не закрылся период", error)
    end
  end
end

# --- 8. Счета-фактуры по документам сквозного сценария (этап 7) ------------
# Счёт-фактура не вводится руками: она формируется по проведённому
# документу, а ставка НДС берётся из законодательных параметров на дату
# документа. Повторный запуск не создаёт дублей.

if admin && primary do
  tenant = primary.id
  actor = Pulse.Core.Actor.build(admin, memberships, tenant)

  form_invoice = fn resource, direction ->
    resource
    |> read_all.(tenant: tenant, load: [:lines])
    |> Enum.filter(&(&1.status == :posted))
    |> Enum.each(fn document ->
      case Pulse.Tax.Invoices.create_from_document(document, direction) do
        {:ok, invoice} ->
          Logger.info("Сформирован счёт-фактура #{invoice.number}")

        {:error, error} ->
          log_error.("Не сформировался счёт-фактура", error)
      end
    end)
  end

  form_invoice.(Pulse.Sales.Shipment, :issued)
  form_invoice.(Pulse.Purchasing.Receipt, :received)

  _ = actor
end

# --- 9. Кадры и зарплата (этап 8) ------------------------------------------
# Демонстрируем расчёт: должности, сотрудники и проведённая ведомость за
# октябрь. Суммы считает `Pulse.Payroll` по параметрам закона.

if admin && primary do
  tenant = primary.id
  actor = Pulse.Core.Actor.build(admin, memberships, tenant)

  seed_hr = fn ->
    if read_all.(Pulse.HR.Position, tenant: tenant) == [] do
      positions = [
        %{code: "DIR", name: "Директор", salary: Decimal.new("600000")},
        %{code: "ACC", name: "Бухгалтер", salary: Decimal.new("350000")},
        %{code: "MGR", name: "Менеджер по продажам", salary: Decimal.new("300000")}
      ]

      created =
        Enum.reduce(positions, [], fn attrs, acc ->
          case create.(Pulse.HR.Position, attrs, tenant: tenant) do
            {:ok, position} ->
              acc ++ [position]

            {:error, error} ->
              log_error.("Не создалась должность #{attrs.code}", error)
              acc
          end
        end)

      people = [
        %{
          last_name: "Киналма",
          first_name: "Аскар",
          middle_name: "Болатович",
          iin: "850101300123"
        },
        %{
          last_name: "Светлова",
          first_name: "Ольга",
          middle_name: "Игоревна",
          iin: "900101501234"
        },
        %{
          last_name: "Омаров",
          first_name: "Бауыржан",
          middle_name: "Талгатович",
          iin: "850712300456"
        }
      ]

      created_people =
        Enum.reduce(people, [], fn attrs, acc ->
          case create.(Pulse.HR.Person, attrs, tenant: tenant) do
            {:ok, person} ->
              acc ++ [person]

            {:error, error} ->
              log_error.("Не создалось физлицо #{attrs.last_name}", error)
              acc
          end
        end)

      Enum.zip(created_people, created)
      |> Enum.each(fn {person, position} ->
        attrs = %{
          person_id: person.id,
          position_id: position && position.id,
          hire_date: ~D[2026-01-01],
          salary: position && position.salary,
          status: :working
        }

        case create.(Pulse.HR.Employee, attrs, tenant: tenant) do
          {:ok, _employee} -> :ok
          {:error, error} -> log_error.("Не создался сотрудник", error)
        end
      end)

      Logger.info("Загружены кадры: #{length(created_people)} сотрудников")
    end
  end

  seed_hr.()

  if read_all.(Pulse.Payroll.Accrual, tenant: tenant) == [] do
    case Pulse.Payroll.Accruals.build(tenant, actor, ~D[2026-10-31], ~D[2026-10-01]) do
      {:ok, accrual} ->
        loaded = Pulse.Payroll.Accruals.load(accrual.id, tenant)

        case Pulse.Accounting.Posting.post(loaded, actor, Pulse.Posting.PayrollAccrual) do
          {:ok, _posted} -> Logger.info("Проведено начисление зарплаты за октябрь")
          {:error, error} -> log_error.("Не провелось начисление зарплаты", error)
        end

      {:error, error} ->
        log_error.("Не построилась ведомость", error)
    end
  end
end

Logger.info(
  "Сиды завершены: этапы 2–8 (справочники, план счетов, сквозной сценарий, " <>
    "деньги, периоды, налоги, кадры и зарплата)"
)
