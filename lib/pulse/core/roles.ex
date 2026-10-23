defmodule Pulse.Core.Roles do
  @moduledoc """
  Фиксированный набор ролей и матрица прав по умолчанию (раздел 7 ТЗ).

  Роли хранятся строками, ключи в коде — атомы. Матрица по умолчанию
  используется сидами и кнопкой «сбросить» в администрировании;
  фактические права всегда читаются из БД (`Pulse.Core.Permissions`).
  """

  @roles %{
    "admin" => "Администратор",
    "chief_accountant" => "Главный бухгалтер",
    "accountant" => "Бухгалтер",
    "payroll_accountant" => "Расчётчик по зарплате",
    "hr_officer" => "Кадровик",
    "storekeeper" => "Кладовщик",
    "cashier" => "Кассир",
    "sales_manager" => "Менеджер по продажам",
    "manager" => "Руководитель",
    "auditor" => "Аудитор"
  }

  @resources ~w(
    core.organization core.department core.membership core.role_permission
    core.period_lock
    catalog.counterparty catalog.contract catalog.nomenclature
    catalog.warehouse catalog.unit catalog.currency catalog.bank
    accounting.account accounting.subaccount_type accounting.entry_template
    accounting.journal_entry
    accounting.document purchasing.receipt sales.shipment
    treasury.cash_flow_item treasury.bank_account treasury.cash_desk
    treasury.bank_document treasury.cash_document
    tax.statutory_rate tax.invoice
    hr.person hr.employee hr.position hr.cadre_document
    payroll.accrual payroll.accrual_line payroll.payment_statement
    ledger.stock_movement ledger.cash_movement ledger.settlement_movement
    ledger.payroll_movement
    accounts.user
  )

  @actions ~w(read create update destroy)

  # Справочники и документы, которые ведёт бухгалтер и кассир.
  @accounting_catalogs ~w(
    accounting.account accounting.subaccount_type accounting.entry_template
  )
  @treasury_catalogs ~w(treasury.cash_flow_item treasury.bank_account treasury.cash_desk)
  @treasury_documents ~w(treasury.bank_document treasury.cash_document)

  @defaults %{
    "admin" => @resources,
    "chief_accountant" =>
      @resources --
        (["core.role_permission"] ++
           Enum.map(@actions, &"core.role_permission.#{&1}")),
    # Бухгалтер ведёт план счетов и типовые операции без релиза.
    "accountant" =>
      Enum.map(@resources, &"#{&1}.read") ++
        Enum.map(
          ~w(catalog.counterparty catalog.contract catalog.nomenclature
             catalog.warehouse catalog.unit catalog.currency),
          &"#{&1}.create"
        ) ++
        Enum.map(
          ~w(catalog.counterparty catalog.contract catalog.nomenclature),
          &"#{&1}.update"
        ) ++
        ["core.organization.read", "core.department.read", "accounts.user.read"] ++
        Enum.map(@accounting_catalogs, &"#{&1}.create") ++
        Enum.map(@accounting_catalogs, &"#{&1}.update"),
    # Кладовщик ведёт складские документы: поступление и реализацию.
    "storekeeper" =>
      Enum.map(
        ~w(catalog.nomenclature catalog.warehouse catalog.unit),
        &"#{&1}.read"
      ) ++
        ["catalog.nomenclature.update", "core.organization.read"] ++
        Enum.map(~w(purchasing.receipt sales.shipment), &"#{&1}.read") ++
        Enum.map(~w(purchasing.receipt sales.shipment), &"#{&1}.create") ++
        Enum.map(~w(purchasing.receipt sales.shipment), &"#{&1}.update") ++
        ["ledger.stock_movement.read", "ledger.stock_movement.create"],
    # Кассир ведёт банк и кассу: справочники, документы и деньги.
    "cashier" =>
      Enum.map(~w(catalog.bank catalog.currency catalog.counterparty), &"#{&1}.read") ++
        ["core.organization.read"] ++
        Enum.map(@treasury_catalogs, &"#{&1}.read") ++
        Enum.map(@treasury_catalogs, &"#{&1}.create") ++
        Enum.map(@treasury_catalogs, &"#{&1}.update") ++
        Enum.map(@treasury_documents, &"#{&1}.read") ++
        Enum.map(@treasury_documents, &"#{&1}.create") ++
        Enum.map(@treasury_documents, &"#{&1}.update") ++
        ["ledger.cash_movement.read", "ledger.cash_movement.create"] ++
        ["ledger.settlement_movement.read", "ledger.settlement_movement.create"],
    # Реализации: менеджер создаёт и проводит.
    "sales_manager" =>
      Enum.map(
        ~w(catalog.counterparty catalog.contract catalog.nomenclature),
        &"#{&1}.read"
      ) ++
        Enum.map(~w(catalog.counterparty catalog.contract), &"#{&1}.create") ++
        Enum.map(~w(catalog.counterparty catalog.contract), &"#{&1}.update") ++
        ["catalog.nomenclature.update", "core.organization.read"] ++
        Enum.map(~w(sales.shipment), &"#{&1}.read") ++
        Enum.map(~w(sales.shipment), &"#{&1}.create") ++
        Enum.map(~w(sales.shipment), &"#{&1}.update") ++
        ["ledger.stock_movement.read"],
    # Расчётчик по зарплате ведёт начисления, выплаты и читает кадры.
    "payroll_accountant" =>
      Enum.map(~w(hr.person hr.employee hr.position hr.cadre_document), &"#{&1}.read") ++
        ["core.organization.read", "core.department.read", "catalog.currency.read"] ++
        Enum.map(
          ~w(payroll.accrual payroll.accrual_line payroll.payment_statement),
          &"#{&1}.read"
        ) ++
        Enum.map(
          ~w(payroll.accrual payroll.accrual_line payroll.payment_statement),
          &"#{&1}.create"
        ) ++
        Enum.map(
          ~w(payroll.accrual payroll.accrual_line payroll.payment_statement),
          &"#{&1}.update"
        ) ++
        ["ledger.payroll_movement.read", "ledger.payroll_movement.create"] ++
        ["treasury.bank_account.read", "treasury.cash_desk.read", "accounting.journal_entry.read"],
    # Кадровик ведёт кадровые документы и справочники сотрудников.
    "hr_officer" =>
      ["core.organization.read", "core.department.read"] ++
        Enum.map(~w(hr.person hr.employee hr.position hr.cadre_document), &"#{&1}.read") ++
        Enum.map(~w(hr.person hr.employee hr.position hr.cadre_document), &"#{&1}.create") ++
        Enum.map(~w(hr.person hr.employee hr.position hr.cadre_document), &"#{&1}.update"),
    "manager" => Enum.map(@resources, &"#{&1}.read"),
    "auditor" => Enum.map(@resources, &"#{&1}.read")
  }

  @doc """
  Все роли в виде `{ключ, название}` для выпадающих списков.
  """
  @spec list() :: [{String.t(), String.t()}]
  def list, do: Enum.map(@roles, fn {key, title} -> {key, title} end)

  @doc """
  Название роли по ключу.
  """
  @spec title(String.t()) :: String.t()
  def title(key), do: Map.get(@roles, key, key)

  @doc """
  Ключи всех ролей.
  """
  @spec keys() :: [String.t()]
  def keys, do: Map.keys(@roles)

  @doc """
  Известные ресурсы матрицы прав.
  """
  @spec resources() :: [String.t()]
  def resources, do: @resources

  @doc """
  Известные действия матрицы прав.
  """
  @spec actions() :: [String.t()]
  def actions, do: @actions

  @doc """
  Матрица прав по умолчанию: `{роль, ресурс, действие}` → `true`.

  Грант вида `"ресурс"` (без действия) раскрывается во все действия.
  Остальные комбинации запрещены (запрет по умолчанию).
  """
  @spec default_matrix() :: [{String.t(), String.t(), String.t()}]
  def default_matrix do
    combos =
      for {role, grants} <- @defaults,
          grant <- grants,
          action <- actions_for(grant) do
        {role, resource_of(grant), action}
      end

    Enum.uniq(combos)
  end

  defp actions_for(grant) do
    case String.split(grant, ".") do
      parts ->
        case List.last(parts) do
          action when action in @actions -> [action]
          _ -> @actions
        end
    end
  end

  defp resource_of(grant) do
    parts = String.split(grant, ".")

    if List.last(parts) in @actions do
      parts |> Enum.drop(-1) |> Enum.join(".")
    else
      grant
    end
  end
end
