defmodule PulseWeb.Reports do
  @moduledoc """
  Реестр бухгалтерских отчётов рабочей области.

  Отчёты меню «Бухгалтерский учет» строятся по журналу проводок
  (`Pulse.Accounting.Reports`). Каждый отчёт описывается заголовком,
  функцией построения и колонками результата.
  """

  alias Pulse.Accounting.Reports

  @doc """
  Спецификация отчёта по заголовку пункта меню.
  """
  @spec spec(String.t()) :: map() | nil
  def spec("Оборотно-сальдовая ведомость (бух.)"), do: trial_balance_spec()
  def spec("Карточка счета (бух.)"), do: account_card_spec()
  def spec("Анализ счета (бух.)"), do: account_analysis_spec()
  def spec("Главная книга (бух.)"), do: general_ledger_spec()
  def spec("Акты сверки взаиморасчетов"), do: reconciliation_spec()
  def spec("Остатки денежных средств"), do: cash_balances_spec()
  def spec("Поступление денежных средств"), do: cash_flow_spec(:receipt)
  def spec("Расход денежных средств"), do: cash_flow_spec(:expense)
  def spec("Кассовая книга"), do: cash_book_spec()
  def spec("Прибыли и убытки"), do: profit_and_loss_spec()
  def spec("Доходы и расходы (прибыль и убыток)"), do: profit_and_loss_spec()
  def spec("Оборачиваемость товаров"), do: inventory_turnover_spec()
  def spec("Журнал учета счетов-фактур"), do: invoice_journal_spec()
  def spec("Отчет по наличию счетов-фактур полученных"), do: received_invoices_spec()
  def spec("Оборотно-сальдовая ведомость (налоговый)"), do: tax_trial_balance_spec()
  def spec("Отчет по проводкам (налоговый)"), do: tax_entries_spec()
  def spec("Расчетные ведомости организаций"), do: payroll_sheet_spec()
  def spec("Расчетные листки организаций"), do: payslip_spec()
  def spec("Свод начислений и удержаний"), do: payroll_summary_spec()
  def spec(_title), do: nil

  @doc """
  Заголовки реализованных отчётов.
  """
  @spec titles() :: [String.t()]
  def titles do
    [
      "Оборотно-сальдовая ведомость (бух.)",
      "Карточка счета (бух.)",
      "Анализ счета (бух.)",
      "Главная книга (бух.)",
      "Акты сверки взаиморасчетов",
      "Остатки денежных средств",
      "Поступление денежных средств",
      "Расход денежных средств",
      "Кассовая книга",
      "Прибыли и убытки",
      "Доходы и расходы (прибыль и убыток)",
      "Оборачиваемость товаров",
      "Журнал учета счетов-фактур",
      "Отчет по наличию счетов-фактур полученных",
      "Оборотно-сальдовая ведомость (налоговый)",
      "Отчет по проводкам (налоговый)",
      "Расчетные ведомости организаций",
      "Расчетные листки организаций",
      "Свод начислений и удержаний"
    ]
  end

  @doc """
  Строит отчёт.

  `params` — то, что ввёл пользователь: счёт и период. Возвращает
  `{:ok, %{columns: columns, rows: rows, totals: totals}}` либо ошибку.
  """
  @spec build(map(), map(), struct()) :: {:ok, map()} | {:error, String.t()}
  def build(spec, params, actor) do
    organization_id = actor.organization_id

    if is_nil(organization_id) do
      {:error, "выберите активную организацию"}
    else
      spec.build.(organization_id, params)
    end
  end

  # ---------------------------------------------------------------------------
  # Оборотно-сальдовая ведомость
  # ---------------------------------------------------------------------------

  defp trial_balance_spec do
    %{
      title: "Оборотно-сальдовая ведомость (бух.)",
      columns: [
        %{key: :code, label: "Счет"},
        %{key: :name, label: "Наименование"},
        %{key: :opening, label: "Сальдо на начало"},
        %{key: :debit, label: "Оборот дебет", align: :right},
        %{key: :credit, label: "Оборот кредит", align: :right},
        %{key: :closing, label: "Сальдо на конец"}
      ],
      build: fn organization_id, params ->
        {from, to} = period(params)
        rows = Reports.trial_balance(organization_id, from, to)
        totals = Reports.trial_balance_totals(rows)

        {:ok,
         %{
           columns: [
             "Счет",
             "Наименование",
             "Сальдо на начало",
             "Оборот дебет",
             "Оборот кредит",
             "Сальдо на конец"
           ],
           rows: Enum.map(rows, &trial_balance_row/1),
           totals: trial_balance_totals(totals),
           period: {from, to}
         }}
      end
    }
  end

  defp trial_balance_row(row) do
    [
      row.code,
      row.name,
      balance_text(row.opening),
      money(row.debit),
      money(row.credit),
      balance_text(row.closing)
    ]
  end

  defp trial_balance_totals(totals) do
    [
      "",
      "Итого",
      balance_text(%{debit: totals.opening_debit, credit: totals.opening_credit}),
      money(totals.debit),
      money(totals.credit),
      balance_text(%{debit: totals.closing_debit, credit: totals.closing_credit})
    ]
  end

  # ---------------------------------------------------------------------------
  # Карточка счета
  # ---------------------------------------------------------------------------

  defp account_card_spec do
    %{
      title: "Карточка счета (бух.)",
      columns: [
        %{key: :doc_date, label: "Дата"},
        %{key: :content, label: "Операция"},
        %{key: :debit, label: "Дебет", align: :right},
        %{key: :credit, label: "Кредит", align: :right},
        %{key: :balance, label: "Сальдо"}
      ],
      account?: true,
      build: fn organization_id, params ->
        account_code = params["account"] || "1330"
        {from, to} = period(params)
        card = Reports.account_card(account_code, organization_id, from, to)

        {:ok,
         %{
           columns: ["Дата", "Операция", "Дебет", "Кредит", "Сальдо"],
           rows:
             Enum.map(card.rows, fn row ->
               [
                 Date.to_string(row.doc_date),
                 row.content || "",
                 money(row.debit),
                 money(row.credit),
                 balance_text(row.balance)
               ]
             end),
           totals: [card.account_code, "Сальдо на конец", "", "", balance_text(card.closing)],
           period: {from, to},
           headline: "Счёт #{card.account_code}: сальдо на начало #{balance_text(card.opening)}"
         }}
      end
    }
  end

  # ---------------------------------------------------------------------------
  # Анализ счета
  # ---------------------------------------------------------------------------

  defp account_analysis_spec do
    %{
      title: "Анализ счета (бух.)",
      columns: [
        %{key: :code, label: "Корреспондирующий счет"},
        %{key: :name, label: "Наименование"},
        %{key: :debit, label: "Дебет", align: :right},
        %{key: :credit, label: "Кредит", align: :right}
      ],
      account?: true,
      build: fn organization_id, params ->
        account_code = params["account"] || "1330"
        {from, to} = period(params)
        rows = Reports.account_analysis(account_code, organization_id, from, to)

        {:ok,
         %{
           columns: ["Корреспондирующий счет", "Наименование", "Дебет", "Кредит"],
           rows: Enum.map(rows, &[&1.code, &1.name, money(&1.debit), money(&1.credit)]),
           totals: ["", "Итого", money(sum(rows, & &1.debit)), money(sum(rows, & &1.credit))],
           period: {from, to},
           headline: "Счёт #{account_code}"
         }}
      end
    }
  end

  # ---------------------------------------------------------------------------
  # Главная книга
  # ---------------------------------------------------------------------------

  defp general_ledger_spec do
    %{
      title: "Главная книга (бух.)",
      columns: [
        %{key: :code, label: "Счет"},
        %{key: :name, label: "Наименование"},
        %{key: :opening, label: "Сальдо на начало"},
        %{key: :debit, label: "Оборот дебет", align: :right},
        %{key: :credit, label: "Оборот кредит", align: :right},
        %{key: :closing, label: "Сальдо на конец"}
      ],
      build: fn organization_id, params ->
        {from, to} = period(params)

        rows =
          organization_id
          |> Reports.general_ledger(from, to)
          |> Enum.flat_map(&ledger_rows/1)

        {:ok,
         %{
           columns: ["Счет", "Корреспонденция", "Дебет", "Кредит", "Сальдо на конец"],
           rows: rows,
           totals: [],
           period: {from, to}
         }}
      end
    }
  end

  defp ledger_rows(account) do
    header = [
      account.code,
      account.name,
      money(account.debit_turnover),
      money(account.credit_turnover),
      balance_text(account.closing)
    ]

    analysis =
      Enum.map(account.analysis, fn row ->
        ["  " <> row.code, row.name, money(row.debit), money(row.credit), ""]
      end)

    [header | analysis]
  end

  # ---------------------------------------------------------------------------
  # Акт сверки взаиморасчётов
  # ---------------------------------------------------------------------------

  defp reconciliation_spec do
    %{
      title: "Акты сверки взаиморасчетов",
      columns: [
        %{key: :doc_date, label: "Дата"},
        %{key: :direction, label: "Операция"},
        %{key: :debit, label: "Дебет", align: :right},
        %{key: :credit, label: "Кредит", align: :right}
      ],
      counterparty?: true,
      build: fn organization_id, params ->
        counterparty_id = params["counterparty"]

        if is_nil(counterparty_id) or counterparty_id == "" do
          {:error, "выберите контрагента"}
        else
          {from, to} = period(params)

          totals =
            Pulse.Settlements.reconciliation_totals(
              organization_id,
              counterparty_id,
              from,
              to
            )

          movements =
            Pulse.Settlements.reconciliation(organization_id, counterparty_id, from, to)

          {:ok,
           %{
             columns: ["Дата", "Операция", "Дебет", "Кредит"],
             rows:
               Enum.map(movements, fn movement ->
                 {debit, credit} = settlement_sides(movement)

                 [
                   Date.to_string(movement.doc_date),
                   settlement_label(movement.direction),
                   money(debit),
                   money(credit)
                 ]
               end),
             totals: [
               "",
               "Сальдо на конец: #{money(totals.closing)}",
               money(totals.debit),
               money(totals.credit)
             ],
             period: {from, to},
             headline: "Сальдо на начало: #{money(totals.opening)}"
           }}
        end
      end
    }
  end

  defp settlement_sides(movement) do
    amount = movement.amount

    case movement.side do
      :debit -> {amount, Decimal.new(0)}
      :credit -> {Decimal.new(0), amount}
    end
  end

  defp settlement_label(:debt), do: "Долг"
  defp settlement_label(:credit), do: "Задолженность"
  defp settlement_label(:payment), do: "Оплата"
  defp settlement_label(:offset), do: "Зачёт аванса"

  # ---------------------------------------------------------------------------
  # Остатки денежных средств
  # ---------------------------------------------------------------------------

  defp cash_balances_spec do
    %{
      title: "Остатки денежных средств",
      columns: [
        %{key: :kind, label: "Вид"},
        %{key: :name, label: "Касса или счёт"},
        %{key: :amount, label: "Остаток", align: :right}
      ],
      build: fn organization_id, params ->
        {_from, to} = period(params)

        balances = Pulse.Settlements.cash_balances(organization_id, to)

        rows =
          Enum.map(balances, fn balance ->
            [
              cash_kind_label(balance.account_kind),
              cash_account_name(organization_id, balance),
              money(balance.amount)
            ]
          end)

        {:ok,
         %{
           columns: ["Вид", "Касса или счёт", "Остаток"],
           rows: rows,
           totals: [
             "",
             "Итого",
             money(sum_decimal(balances, & &1.amount))
           ],
           period: {to, to}
         }}
      end
    }
  end

  # ---------------------------------------------------------------------------
  # Поступление и расход денежных средств
  # ---------------------------------------------------------------------------

  defp cash_flow_spec(direction) do
    %{
      title:
        if(direction == :receipt,
          do: "Поступление денежных средств",
          else: "Расход денежных средств"
        ),
      columns: [
        %{key: :doc_date, label: "Дата"},
        %{key: :number, label: "Номер"},
        %{key: :account, label: "Касса или счёт"},
        %{key: :amount, label: "Сумма", align: :right}
      ],
      build: fn organization_id, params ->
        {from, to} = period(params)

        movements =
          Pulse.Treasury.cash_flow(organization_id, direction, from, to)

        {:ok,
         %{
           columns: ["Дата", "Номер", "Касса или счёт", "Сумма"],
           rows:
             Enum.map(movements, fn movement ->
               [
                 Date.to_string(movement.doc_date),
                 movement.document_number,
                 movement.account_name,
                 money(movement.amount)
               ]
             end),
           totals: [
             "",
             "",
             "Итого",
             money(sum_decimal(movements, & &1.amount))
           ],
           period: {from, to}
         }}
      end
    }
  end

  # ---------------------------------------------------------------------------
  # Кассовая книга
  # ---------------------------------------------------------------------------

  defp cash_book_spec do
    %{
      title: "Кассовая книга",
      columns: [
        %{key: :doc_date, label: "Дата"},
        %{key: :number, label: "Номер"},
        %{key: :content, label: "Операция"},
        %{key: :debit, label: "Приход", align: :right},
        %{key: :credit, label: "Расход", align: :right}
      ],
      build: fn organization_id, params ->
        {from, to} = period(params)

        movements = Pulse.Treasury.cash_book(organization_id, from, to)

        {rows, totals} =
          Enum.reduce(movements, {[], {Decimal.new(0), Decimal.new(0)}}, fn movement,
                                                                            {rows, totals} ->
            {debit, credit} =
              if movement.record_type == :receipt do
                {movement.amount, Decimal.new(0)}
              else
                {Decimal.new(0), movement.amount}
              end

            row = [
              Date.to_string(movement.doc_date),
              movement.document_number,
              movement.content,
              money(debit),
              money(credit)
            ]

            {totals_debit, totals_credit} = totals

            {rows ++ [row],
             {
               Decimal.add(totals_debit, debit),
               Decimal.add(totals_credit, credit)
             }}
          end)

        {totals_debit, totals_credit} = totals

        {:ok,
         %{
           columns: ["Дата", "Номер", "Операция", "Приход", "Расход"],
           rows: rows,
           totals: ["", "", "Итого", money(totals_debit), money(totals_credit)],
           period: {from, to},
           headline: "Кассовые документы за период"
         }}
      end
    }
  end

  # ---------------------------------------------------------------------------
  # Общее
  # ---------------------------------------------------------------------------

  # ---------------------------------------------------------------------------
  # Прибыли и убытки
  # ---------------------------------------------------------------------------

  defp profit_and_loss_spec do
    %{
      title: "Прибыли и убытки",
      columns: [
        %{key: :kind, label: "Показатель"},
        %{key: :code, label: "Счет"},
        %{key: :name, label: "Наименование"},
        %{key: :amount, label: "Сумма", align: :right}
      ],
      build: fn organization_id, params ->
        {from, to} = period(params)
        report = Pulse.Reporting.ProfitAndLoss.report(organization_id, from, to)

        rows =
          Enum.map(report.income, fn row ->
            ["Доход", row.code, row.name, money(row.amount)]
          end) ++
            Enum.map(report.expenses, fn row ->
              ["Расход", row.code, row.name, money(row.amount)]
            end)

        {:ok,
         %{
           columns: ["Показатель", "Счет", "Наименование", "Сумма"],
           rows: rows,
           totals: [
             "Прибыль",
             "",
             "Доходы #{money(report.income_total)} − расходы #{money(report.expense_total)}",
             money(report.profit)
           ],
           period: {from, to},
           headline:
             if(
               Decimal.compare(report.profit, 0) == :lt,
               do: "Убыток за период: #{money(Decimal.negate(report.profit))}",
               else: "Прибыль за период: #{money(report.profit)}"
             )
         }}
      end
    }
  end

  # ---------------------------------------------------------------------------
  # Оборачиваемость товаров
  # ---------------------------------------------------------------------------

  defp inventory_turnover_spec do
    %{
      title: "Оборачиваемость товаров",
      columns: [
        %{key: :name, label: "Показатель"},
        %{key: :value, label: "Значение", align: :right}
      ],
      build: fn organization_id, params ->
        {from, to} = period(params)
        turnover = Pulse.Reporting.ProfitAndLoss.inventory_turnover(organization_id, from, to)

        {:ok,
         %{
           columns: ["Показатель", "Значение"],
           rows: [
             ["Средний остаток по себестоимости", money(turnover.average_cost)],
             ["Себестоимость проданного", money(turnover.sold_cost)],
             ["Оборачиваемость, раз", money(turnover.turnover)]
           ],
           totals: [],
           period: {from, to}
         }}
      end
    }
  end

  # ---------------------------------------------------------------------------
  # Налоговый контур: журналы счетов-фактур и отчёты (этап 7)
  # ---------------------------------------------------------------------------

  defp invoice_journal_spec do
    %{
      title: "Журнал учета счетов-фактур",
      columns: [
        %{key: :direction, label: "Направление"},
        %{key: :number, label: "Номер"},
        %{key: :date, label: "Дата"},
        %{key: :net, label: "Без НДС", align: :right},
        %{key: :vat, label: "НДС", align: :right},
        %{key: :gross, label: "С НДС", align: :right}
      ],
      build: fn organization_id, params ->
        {from, to} = period(params)
        issued = Pulse.Tax.Invoices.list(organization_id, :issued, from, to)
        received = Pulse.Tax.Invoices.list(organization_id, :received, from, to)

        rows =
          Enum.map(issued, &invoice_row(&1, "Выданный")) ++
            Enum.map(received, &invoice_row(&1, "Полученный"))

        issued_totals = Pulse.Tax.Invoices.totals(issued)
        received_totals = Pulse.Tax.Invoices.totals(received)

        {:ok,
         %{
           columns: ["Направление", "Номер", "Дата", "Без НДС", "НДС", "С НДС"],
           rows: rows,
           totals: [
             "Итого",
             "",
             "",
             "",
             money(Decimal.sub(received_totals.vat, issued_totals.vat)),
             ""
           ],
           period: {from, to},
           headline:
             "НДС к уплате: #{money(issued_totals.vat)} · НДС к зачёту: #{money(received_totals.vat)}"
         }}
      end
    }
  end

  defp received_invoices_spec do
    %{
      title: "Отчет по наличию счетов-фактур полученных",
      columns: [
        %{key: :number, label: "Номер"},
        %{key: :date, label: "Дата"},
        %{key: :net, label: "Без НДС", align: :right},
        %{key: :vat, label: "НДС", align: :right},
        %{key: :gross, label: "С НДС", align: :right}
      ],
      build: fn organization_id, params ->
        {from, to} = period(params)
        invoices = Pulse.Tax.Invoices.list(organization_id, :received, from, to)
        totals = Pulse.Tax.Invoices.totals(invoices)

        {:ok,
         %{
           columns: ["Номер", "Дата", "Без НДС", "НДС", "С НДС"],
           rows: Enum.map(invoices, &invoice_row(&1, nil)),
           totals: ["Итого", "", money(totals.net), money(totals.vat), money(totals.gross)],
           period: {from, to},
           headline: "Полученных счетов-фактур: #{length(invoices)}"
         }}
      end
    }
  end

  defp tax_trial_balance_spec do
    %{
      title: "Оборотно-сальдовая ведомость (налоговый)",
      columns: [
        %{key: :code, label: "Счет"},
        %{key: :name, label: "Наименование"},
        %{key: :opening, label: "Сальдо на начало"},
        %{key: :debit, label: "Оборот дебет", align: :right},
        %{key: :credit, label: "Оборот кредит", align: :right},
        %{key: :closing, label: "Сальдо на конец"}
      ],
      build: fn organization_id, params ->
        {from, to} = period(params)
        rows = Reports.trial_balance(organization_id, from, to, ledger: :tax)

        {:ok,
         %{
           columns: [
             "Счет",
             "Наименование",
             "Сальдо на начало",
             "Оборот дебет",
             "Оборот кредит",
             "Сальдо на конец"
           ],
           rows: Enum.map(rows, &trial_balance_row/1),
           totals: trial_balance_totals(Reports.trial_balance_totals(rows)),
           period: {from, to},
           headline: "Налоговый учёт отделён от бухгалтерского"
         }}
      end
    }
  end

  defp tax_entries_spec do
    %{
      title: "Отчет по проводкам (налоговый)",
      columns: [
        %{key: :date, label: "Дата"},
        %{key: :debit, label: "Дебет"},
        %{key: :credit, label: "Кредит"},
        %{key: :content, label: "Содержание"},
        %{key: :amount, label: "Сумма", align: :right}
      ],
      build: fn organization_id, params ->
        {from, to} = period(params)
        entries = Pulse.Accounting.Entries.entries(organization_id, from, to, ledger: :tax)

        {:ok,
         %{
           columns: ["Дата", "Дебет", "Кредит", "Содержание", "Сумма"],
           rows:
             Enum.map(entries, fn entry ->
               [
                 Date.to_string(entry.doc_date),
                 entry.debit_account_code,
                 entry.credit_account_code,
                 entry.content || "",
                 money(entry.amount)
               ]
             end),
           totals: [],
           period: {from, to},
           headline: "Проводок налогового учёта: #{length(entries)}"
         }}
      end
    }
  end

  # ---------------------------------------------------------------------------
  # Зарплата (этап 8)
  # ---------------------------------------------------------------------------

  defp payroll_sheet_spec do
    %{
      title: "Расчетные ведомости организаций",
      employee?: true,
      columns: [
        %{key: :employee, label: "Сотрудник"},
        %{key: :gross, label: "Начислено", align: :right},
        %{key: :opv, label: "ОПВ", align: :right},
        %{key: :vosms, label: "ВОСМС", align: :right},
        %{key: :ipn, label: "ИПН", align: :right},
        %{key: :net, label: "К выплате", align: :right}
      ],
      build: fn organization_id, params ->
        {from, to} = period(params)
        movements = payroll_movements(organization_id, from, to)

        rows =
          movements
          |> group_by_employee()
          |> Enum.sort_by(fn {_id, data} -> data.name end)
          |> Enum.map(fn {_id, data} ->
            [
              data.name,
              money(data.gross),
              money(data.opv),
              money(data.vosms),
              money(data.ipn),
              money(data.net)
            ]
          end)

        totals = sum_kinds(movements)

        {:ok,
         %{
           columns: ["Сотрудник", "Начислено", "ОПВ", "ВОСМС", "ИПН", "К выплате"],
           rows: rows,
           totals: [
             "Итого",
             money(totals.gross),
             money(totals.opv),
             money(totals.vosms),
             money(totals.ipn),
             money(totals.net)
           ],
           period: {from, to},
           headline: "Сотрудников в расчёте: #{length(rows)}"
         }}
      end
    }
  end

  defp payslip_spec do
    %{
      title: "Расчетные листки организаций",
      employee?: true,
      columns: [
        %{key: :kind, label: "Показатель"},
        %{key: :amount, label: "Сумма", align: :right}
      ],
      build: fn organization_id, params ->
        {from, to} = period(params)

        case params["employee"] do
          value when is_binary(value) and value != "" ->
            movements =
              organization_id
              |> payroll_movements(from, to)
              |> Enum.filter(&(&1.employee_id == value))

            {:ok,
             %{
               columns: ["Показатель", "Сумма"],
               rows: movements |> sum_kinds() |> payslip_rows(),
               totals: [],
               period: {from, to},
               headline: "Расчётный листок за период"
             }}

          _ ->
            {:error, "выберите сотрудника"}
        end
      end
    }
  end

  defp payroll_summary_spec do
    %{
      title: "Свод начислений и удержаний",
      columns: [
        %{key: :kind, label: "Показатель"},
        %{key: :amount, label: "Сумма", align: :right}
      ],
      build: fn organization_id, params ->
        {from, to} = period(params)
        totals = organization_id |> payroll_movements(from, to) |> sum_kinds()

        {:ok,
         %{
           columns: ["Показатель", "Сумма"],
           rows: payslip_rows(totals),
           totals: [],
           period: {from, to},
           headline:
             "К выплате: #{money(totals.net)} · начислено: #{money(totals.gross)} · ИПН: #{money(totals.ipn)}"
         }}
      end
    }
  end

  defp payroll_movements(organization_id, from, to) do
    require Ash.Query

    Pulse.Ledger.PayrollMovement
    |> Ash.Query.filter(period >= ^month_start(from) and period <= ^month_start(to))
    |> Ash.read(tenant: organization_id, authorize?: false)
    |> case do
      {:ok, movements} -> movements
      _ -> []
    end
  end

  defp month_start(%Date{year: year, month: month}), do: %Date{year: year, month: month, day: 1}

  defp group_by_employee(movements) do
    movements
    |> Enum.group_by(& &1.employee_id)
    |> Map.new(fn {employee_id, list} ->
      {employee_id, Map.put(sum_kinds(list), :name, employee_label(employee_id))}
    end)
  end

  defp employee_label(employee_id) do
    case Ash.get(Pulse.HR.Employee, employee_id, authorize?: false) do
      {:ok, employee} -> employee_label_for(employee)
      _ -> employee_id
    end
  end

  defp employee_label_for(%{person: %Ash.NotLoaded{}} = employee), do: employee.id
  defp employee_label_for(%{person: nil} = employee), do: employee.id
  defp employee_label_for(%{person: person}), do: Pulse.HR.Person.full_name(person)

  defp sum_kinds(movements) do
    base = %{
      gross: zero(),
      opv: zero(),
      vosms: zero(),
      ipn: zero(),
      so: zero(),
      opvr: zero(),
      oosms: zero(),
      payment: zero()
    }

    summed =
      Enum.reduce(movements, base, fn movement, acc ->
        if Map.has_key?(acc, movement.kind) do
          Map.update!(acc, movement.kind, &Decimal.add(&1, movement.amount))
        else
          acc
        end
      end)

    Map.put(
      summed,
      :net,
      Decimal.sub(summed.gross, Decimal.add(summed.ipn, Decimal.add(summed.opv, summed.vosms)))
    )
  end

  defp payslip_rows(totals) do
    [
      ["Начислено", money(totals.gross)],
      ["ОПВ", money(totals.opv)],
      ["ВОСМС", money(totals.vosms)],
      ["ИПН", money(totals.ipn)],
      ["Социальные отчисления", money(totals.so)],
      ["ОПВР", money(total(totals.opvr))],
      ["ООСМС", money(totals.oosms)],
      ["К выплате", money(totals.net)]
    ]
  end

  defp total(value), do: value || zero()

  defp zero, do: Decimal.new(0)

  defp invoice_row(invoice, direction) do
    net = Pulse.Tax.Invoice.net_amount(invoice.amount, invoice.vat_rate)
    vat = invoice.vat_amount || Decimal.new(0)

    base = [
      invoice.number,
      Date.to_string(invoice.invoice_date),
      money(net),
      money(vat),
      money(invoice.amount)
    ]

    if direction, do: [direction | base], else: base
  end

  defp cash_kind_label(:cash), do: "Касса"
  defp cash_kind_label(:bank), do: "Банковский счёт"

  defp cash_account_name(organization_id, %{account_kind: kind, account_id: id}) do
    Pulse.Treasury.account_name(organization_id, kind, id)
  end

  defp sum_decimal(rows, fun) do
    Enum.reduce(rows, Decimal.new(0), fn row, acc -> Decimal.add(acc, fun.(row)) end)
  end

  # Период отчёта: пользователь задаёт строки, по умолчанию — текущий месяц.
  defp period(params) do
    today = Date.utc_today()

    from =
      case params["from"] do
        value when is_binary(value) and value != "" -> Date.from_iso8601!(value)
        _ -> %Date{year: today.year, month: today.month, day: 1}
      end

    to =
      case params["to"] do
        value when is_binary(value) and value != "" -> Date.from_iso8601!(value)
        _ -> Date.add(from, 30)
      end

    {from, to}
  end

  defp money(nil), do: "—"

  defp money(value) do
    value
    |> Decimal.round(2)
    |> Decimal.to_string()
  end

  defp balance_text(%{debit: debit, credit: credit}) do
    cond do
      Decimal.equal?(debit, 0) and Decimal.equal?(credit, 0) -> "—"
      Decimal.equal?(credit, 0) -> "#{money(debit)} Дт"
      Decimal.equal?(debit, 0) -> "#{money(credit)} Кт"
      true -> "#{money(debit)} Дт / #{money(credit)} Кт"
    end
  end

  defp sum(rows, fun) do
    Enum.reduce(rows, Decimal.new(0), fn row, acc -> Decimal.add(acc, fun.(row)) end)
  end
end
