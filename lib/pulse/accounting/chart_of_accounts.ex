defmodule Pulse.Accounting.ChartOfAccounts do
  @moduledoc """
  Типовой план счетов Республики Казахстан и шаблоны проводок по умолчанию.

  Данные хранятся кодом по двум причинам: так их видно в ревью и так
  они версионируются вместе с логикой. Значения — не истина в последней
  инстанции: бухгалтер правит счета и шаблоны через интерфейс без релиза
  (`Pulse.Accounting.Account`, `Pulse.Accounting.EntryTemplate`).

  **Внимание.** Коды и наименования приведены по типовому плану счетов
  РК и подлежат сверке с действующей редакцией (раздел 5.5 ТЗ): часть
  кодов в прототипе — предположение, а не проверенное значение.
  """

  @accounts [
    # Раздел I. Краткосрочные активы
    %{code: "1010", name: "Денежные средства в кассе", kind: :active},
    %{code: "1030", name: "Денежные средства на текущих банковских счетах", kind: :active},
    %{code: "1050", name: "Денежные средства на сберегательных счетах", kind: :active},
    %{
      code: "1210",
      name: "Краткосрочная дебиторская задолженность покупателей и заказчиков",
      kind: :active,
      subaccount_codes: ["counterparty", "contract"]
    },
    %{code: "1250", name: "Краткосрочная дебиторская задолженность работников", kind: :active},
    %{code: "1310", name: "Авансы выданные", kind: :active, subaccount_codes: ["counterparty"]},
    %{
      code: "1330",
      name: "Товары",
      kind: :active,
      subaccount_codes: ["nomenclature", "warehouse"],
      quantity: true
    },
    %{
      code: "1350",
      name: "Готовая продукция",
      kind: :active,
      subaccount_codes: ["nomenclature", "warehouse"],
      quantity: true
    },
    %{code: "1420", name: "Налог на добавленную стоимость", kind: :active},

    # Раздел II. Долгосрочные активы
    %{code: "2410", name: "Основные средства", kind: :active},
    %{code: "2420", name: "Амортизация основных средств", kind: :passive},

    # Раздел III. Краткосрочные обязательства
    %{
      code: "3310",
      name: "Краткосрочная кредиторская задолженность поставщикам и подрядчикам",
      kind: :passive,
      subaccount_codes: ["counterparty", "contract"]
    },
    %{
      code: "3350",
      name: "Краткосрочная кредиторская задолженность по оплате труда",
      kind: :passive
    },
    %{code: "3410", name: "Налоги, сборы и обязательные платежи", kind: :passive},
    %{code: "3420", name: "Налог на добавленную стоимость", kind: :passive},
    %{code: "3430", name: "Индивидуальный подоходный налог", kind: :passive},
    %{code: "3120", name: "Обязательства по пенсионным взносам", kind: :passive},
    %{code: "3130", name: "Обязательства по социальным отчислениям", kind: :passive},
    %{
      code: "3140",
      name: "Обязательства по социальному медицинскому страхованию",
      kind: :passive
    },
    %{
      code: "3510",
      name: "Краткосрочные авансы полученные",
      kind: :passive,
      subaccount_codes: ["counterparty"]
    },

    # Раздел IV. Долгосрочные обязательства
    %{code: "4010", name: "Долгосрочные займы", kind: :passive},

    # Раздел V. Капитал
    %{code: "5030", name: "Неоплаченный капитал", kind: :active},
    %{code: "5610", name: "Нераспределенная прибыль (непокрытый убыток)", kind: :active_passive},

    # Раздел VI. Доходы
    %{
      code: "6010",
      name: "Доход от реализации продукции и оказания услуг",
      kind: :passive,
      subaccount_codes: ["counterparty", "nomenclature"]
    },
    %{code: "6280", name: "Прочие доходы", kind: :passive},

    # Раздел VII. Расходы
    %{
      code: "7010",
      name: "Себестоимость реализованной продукции и оказанных услуг",
      kind: :active,
      subaccount_codes: ["nomenclature"]
    },
    %{code: "7210", name: "Административные расходы", kind: :active},
    %{code: "7470", name: "Прочие расходы", kind: :active},

    # Забалансовые
    %{code: "001", name: "Арендованные основные средства", kind: :active, off_balance: true},
    %{
      code: "002",
      name: "Товарно-материальные ценности, принятые на ответственное хранение",
      kind: :active,
      off_balance: true
    }
  ]

  @subaccount_types [
    %{code: "counterparty", name: "Контрагенты", reference: "catalog.counterparty"},
    %{code: "nomenclature", name: "Номенклатура", reference: "catalog.nomenclature"},
    %{code: "warehouse", name: "Склады", reference: "catalog.warehouse"},
    %{code: "contract", name: "Договоры", reference: "catalog.contract"},
    %{code: "department", name: "Подразделения", reference: "core.department"}
  ]

  @templates [
    %{
      kind: :receipt_tmz,
      name: "Поступление ТМЗ и услуг",
      debit_account_code: "1330",
      credit_account_code: "3310",
      debit_subaccount_codes: ["nomenclature", "warehouse"],
      credit_subaccount_codes: ["counterparty"],
      note: "Оприходование товаров от поставщика"
    },
    %{
      kind: :shipment_tmz,
      name: "Реализация ТМЗ и услуг",
      debit_account_code: "1210",
      credit_account_code: "6010",
      debit_subaccount_codes: ["counterparty"],
      credit_subaccount_codes: ["nomenclature"],
      note: "Реализация товаров покупателю"
    },
    %{
      kind: :receipt_service,
      name: "Поступление услуг",
      debit_account_code: "7210",
      credit_account_code: "3310",
      credit_subaccount_codes: ["counterparty"],
      note: "Услуги сторонних организаций"
    },
    %{
      kind: :shipment_service,
      name: "Реализация услуг",
      debit_account_code: "1210",
      credit_account_code: "6010",
      debit_subaccount_codes: ["counterparty"],
      note: "Оказание услуг заказчику"
    },
    %{
      kind: :cash_receipt,
      name: "Поступление в кассу",
      debit_account_code: "1010",
      credit_account_code: "1210",
      credit_subaccount_codes: ["counterparty"],
      note: "Оплата от покупателя наличными"
    },
    %{
      kind: :cash_payment,
      name: "Выплата из кассы",
      debit_account_code: "3310",
      credit_account_code: "1010",
      debit_subaccount_codes: ["counterparty"],
      note: "Оплата поставщику наличными"
    },
    %{
      kind: :bank_receipt,
      name: "Поступление на банковский счёт",
      debit_account_code: "1030",
      credit_account_code: "1210",
      credit_subaccount_codes: ["counterparty"],
      note: "Оплата от покупателя по банку"
    },
    %{
      kind: :bank_payment,
      name: "Списание с банковского счёта",
      debit_account_code: "3310",
      credit_account_code: "1030",
      debit_subaccount_codes: ["counterparty"],
      note: "Оплата поставщику по банку"
    },
    %{
      kind: :payroll_accrual,
      name: "Начисление заработной платы",
      debit_account_code: "7210",
      credit_account_code: "3350",
      note: "Начислена заработная плата работникам"
    },
    %{
      kind: :payroll_ipn,
      name: "Удержание ИПН",
      debit_account_code: "3350",
      credit_account_code: "3430",
      note: "Удержан индивидуальный подоходный налог"
    },
    %{
      kind: :payroll_opv,
      name: "Удержание ОПВ и ВОСМС",
      debit_account_code: "3350",
      credit_account_code: "3120",
      note: "Удержаны пенсионные взносы и взносы ОСМС"
    },
    %{
      kind: :payroll_employer,
      name: "Взносы и отчисления работодателя",
      debit_account_code: "7210",
      credit_account_code: "3130",
      note: "Социальные отчисления, ОПВР и ООСМС работодателя"
    },
    %{
      kind: :payroll_payment,
      name: "Выплата заработной платы",
      debit_account_code: "3350",
      credit_account_code: "1030",
      note: "Выплата заработной платы через банк (или кассу)"
    }
  ]

  @doc "Счета типового плана."
  @spec accounts() :: [map()]
  def accounts, do: @accounts

  @doc "Виды субконто."
  @spec subaccount_types() :: [map()]
  def subaccount_types, do: @subaccount_types

  @doc "Шаблоны проводок по умолчанию."
  @spec templates() :: [map()]
  def templates, do: @templates

  @doc """
  Шаблон по виду операции (для сидов и тестов).
  """
  @spec template(atom()) :: map() | nil
  def template(kind), do: Enum.find(@templates, &(&1.kind == kind))
end
