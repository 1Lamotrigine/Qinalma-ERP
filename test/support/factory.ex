defmodule Pulse.Factory do
  @moduledoc """
  Фабрики тестовых данных.
  """

  alias Pulse.Accounts.User
  alias Pulse.Catalog
  alias Pulse.Core

  @doc """
  Создаёт пользователя с указанным или случайным email.
  """
  def create_user(attrs \\ %{}) do
    email = Map.get(attrs, :email, "user#{System.unique_integer([:positive])}@qinalma.local")
    password = Map.get(attrs, :password, "password123456")

    User
    |> Ash.Changeset.for_create(
      :register_with_password,
      %{email: email, password: password, password_confirmation: password}
    )
    |> Ash.create!(domain: Pulse.Accounts)
  end

  @doc """
  Создаёт организацию с указанными атрибутами.
  """
  def create_organization(attrs \\ %{}) do
    attrs =
      attrs
      |> Map.put_new(:name, "ООО «Тест-#{System.unique_integer([:positive])}»")
      |> Map.put_new(:bin, random_digits(12))

    Ash.Changeset.for_create(Core.Organization, :create, attrs)
    |> Ash.create!(authorize?: false)
  end

  @doc """
  Добавляет пользователя в организацию с указанной ролью.
  """
  def create_membership(user, organization, role \\ "admin") do
    Ash.Changeset.for_create(Core.OrganizationMembership, :create, %{
      user_id: user.id,
      organization_id: organization.id,
      role: role
    })
    |> Ash.create!(authorize?: false)
  end

  @doc """
  Создаёт пользователя с организацией и возвращает актор запроса.

  Можно переиспользовать существующую организацию — тогда роль актора
  задаётся для неё (нужно, чтобы несколько ролей работали в одной
  организации).
  """
  def create_actor(role \\ "admin", organization_id \\ nil) do
    user = create_user()
    organization = organization_for(organization_id)
    create_membership(user, organization, role)

    Pulse.Core.Actor.build(user, [membership_dto(organization, role)], organization.id)
  end

  defp organization_for(nil), do: create_organization()

  defp organization_for(organization_id) do
    Ash.get!(Pulse.Core.Organization, organization_id, authorize?: false)
  end

  @doc """
  Членство в виде простой карты для `Pulse.Core.Actor.build/3`.
  """
  def membership_dto(organization, role) do
    %{organization_id: organization.id, role: role}
  end

  @doc """
  Загружает матрицу прав по умолчанию и перезагружает кэш.
  """
  def seed_default_permissions! do
    for {role, resource, action} <- Core.Roles.default_matrix() do
      Ash.Changeset.for_create(Core.RolePermission, :create, %{
        role: role,
        resource: resource,
        action: action,
        allowed?: true
      })
      |> Ash.create!(authorize?: false)
    end

    Pulse.Core.Permissions.reload()
  end

  @doc """
  Создаёт контрагента в организации актора.
  """
  def create_counterparty(actor, attrs \\ %{}) do
    attrs =
      attrs
      |> Map.put_new(:name, "Контрагент-#{System.unique_integer([:positive])}")
      |> Map.put_new(:kind, :legal)
      |> Map.put_new(:bin, random_digits(12))

    Ash.Changeset.for_create(Catalog.Counterparty, :create, attrs)
    |> Ash.Changeset.set_tenant(actor.organization_id)
    |> Ash.create!(actor: actor)
  end

  @doc """
  Создаёт номенклатуру в организации актора.
  """
  def create_nomenclature(actor, attrs \\ %{}) do
    attrs =
      attrs
      |> Map.put_new(:name, "Товар-#{System.unique_integer([:positive])}")
      |> Map.put_new(:kind, :product)
      |> Map.put_new(:code, "N-#{System.unique_integer([:positive])}")
      |> Map.put_new(:price, Decimal.new("100.00"))

    Ash.Changeset.for_create(Catalog.Nomenclature, :create, attrs)
    |> Ash.Changeset.set_tenant(actor.organization_id)
    |> Ash.create!(actor: actor)
  end

  @doc """
  Загружает план счетов, виды субконто и шаблоны проводок.
  """
  def seed_chart_of_accounts! do
    alias Pulse.Accounting.ChartOfAccounts

    Enum.each(ChartOfAccounts.subaccount_types(), fn attrs ->
      Ash.Changeset.for_create(Pulse.Accounting.SubaccountType, :create, attrs)
      |> Ash.create!(authorize?: false)
    end)

    Enum.each(ChartOfAccounts.accounts(), fn attrs ->
      attrs = Map.put_new(attrs, :subaccount_codes, [])

      Ash.Changeset.for_create(Pulse.Accounting.Account, :create, attrs)
      |> Ash.create!(authorize?: false)
    end)

    Enum.each(ChartOfAccounts.templates(), fn attrs ->
      Ash.Changeset.for_create(Pulse.Accounting.EntryTemplate, :create, attrs)
      |> Ash.create!(authorize?: false)
    end)
  end

  @doc """
  Создаёт банковский счёт в организации актора.
  """
  def create_bank_account(actor, attrs \\ %{}) do
    attrs =
      attrs
      |> Map.put_new(:name, "Счёт-#{System.unique_integer([:positive])}")
      |> Map.put_new(:account_number, "KZ#{random_digits(18)}")

    Ash.Changeset.for_create(Pulse.Treasury.BankAccount, :create, attrs)
    |> Ash.Changeset.set_tenant(actor.organization_id)
    |> Ash.create!(actor: actor)
  end

  @doc """
  Создаёт кассу в организации актора.
  """
  def create_cash_desk(actor, attrs \\ %{}) do
    attrs =
      attrs
      |> Map.put_new(:name, "Касса-#{System.unique_integer([:positive])}")
      |> Map.put_new(:code, "CASH-#{System.unique_integer([:positive])}")

    Ash.Changeset.for_create(Pulse.Treasury.CashDesk, :create, attrs)
    |> Ash.Changeset.set_tenant(actor.organization_id)
    |> Ash.create!(actor: actor)
  end

  @doc """
  Создаёт статью движения денежных средств.
  """
  def create_cash_flow_item(actor, attrs \\ %{}) do
    attrs =
      attrs
      |> Map.put_new(:name, "Статья-#{System.unique_integer([:positive])}")
      |> Map.put_new(:kind, :receipt)

    Ash.Changeset.for_create(Pulse.Treasury.CashFlowItem, :create, attrs)
    |> Ash.Changeset.set_tenant(actor.organization_id)
    |> Ash.create!(actor: actor)
  end

  @doc """
  Создаёт склад в организации актора.
  """
  def create_warehouse(actor, attrs \\ %{}) do
    attrs =
      attrs
      |> Map.put_new(:name, "Склад-#{System.unique_integer([:positive])}")
      |> Map.put_new(:code, "WH-#{System.unique_integer([:positive])}")

    Ash.Changeset.for_create(Catalog.Warehouse, :create, attrs)
    |> Ash.Changeset.set_tenant(actor.organization_id)
    |> Ash.create!(actor: actor)
  end

  @doc """
  Создаёт законодательный параметр (ставку, порог).
  """
  def create_statutory_rate(attrs \\ %{}) do
    attrs =
      attrs
      |> Map.put_new(:code, "vat_rate")
      |> Map.put_new(:value, Decimal.new("16"))
      |> Map.put_new(:valid_from, ~D[2026-01-01])

    Ash.Changeset.for_create(Pulse.Tax.StatutoryRate, :create, attrs)
    |> Ash.create!(authorize?: false)
  end

  @doc """
  Создаёт счёт-фактуру в организации актора.
  """
  def create_invoice(actor, attrs \\ %{}) do
    attrs =
      attrs
      |> Map.put_new(:direction, :issued)
      |> Map.put_new(:number, "СФ-#{System.unique_integer([:positive])}")
      |> Map.put_new(:invoice_date, ~D[2026-10-10])
      |> Map.put_new(:amount, Decimal.new("116000"))
      |> Map.put_new(:vat_rate, Decimal.new("16"))

    attrs =
      if Map.has_key?(attrs, :vat_amount) or is_nil(attrs[:vat_rate]) do
        attrs
      else
        Map.put(attrs, :vat_amount, Pulse.Tax.Invoice.vat_amount(attrs.amount, attrs.vat_rate))
      end

    Ash.Changeset.for_create(Pulse.Tax.Invoice, :create, attrs)
    |> Ash.Changeset.set_tenant(actor.organization_id)
    |> Ash.create!(authorize?: false)
  end

  @doc """
  Загружает значения законодательных параметров по умолчанию.
  """
  def seed_statutory_rates! do
    Enum.each(Pulse.Tax.StatutoryRates.defaults(), fn attrs ->
      Ash.Changeset.for_create(Pulse.Tax.StatutoryRate, :create, attrs)
      |> Ash.create!(authorize?: false)
    end)
  end

  @doc """
  Создаёт физлицо в организации актора.
  """
  def create_person(actor, attrs \\ %{}) do
    attrs =
      attrs
      |> Map.put_new(:last_name, "Тестов")
      |> Map.put_new(:first_name, "Тест")
      |> Map.put_new(:iin, "900101500123")

    Ash.Changeset.for_create(Pulse.HR.Person, :create, attrs)
    |> Ash.Changeset.set_tenant(actor.organization_id)
    |> Ash.create!(actor: actor)
  end

  @doc """
  Создаёт должность в организации актора.
  """
  def create_position(actor, attrs \\ %{}) do
    attrs =
      attrs
      |> Map.put_new(:name, "Должность-#{System.unique_integer([:positive])}")
      |> Map.put_new(:code, "POS-#{System.unique_integer([:positive])}")
      |> Map.put_new(:salary, Decimal.new("200000"))

    Ash.Changeset.for_create(Pulse.HR.Position, :create, attrs)
    |> Ash.Changeset.set_tenant(actor.organization_id)
    |> Ash.create!(actor: actor)
  end

  @doc """
  Создаёт сотрудника в организации актора.
  """
  def create_employee(actor, attrs \\ %{}) do
    person = Map.get_lazy(attrs, :person_id, fn -> create_person(actor).id end)

    attrs =
      attrs
      |> Map.put_new(:person_id, person)
      |> Map.put_new(:hire_date, ~D[2026-01-01])
      |> Map.put_new(:salary, Decimal.new("200000"))
      |> Map.put_new(:status, :working)

    Ash.Changeset.for_create(Pulse.HR.Employee, :create, attrs)
    |> Ash.Changeset.set_tenant(actor.organization_id)
    |> Ash.create!(actor: actor)
  end

  defp random_digits(count) do
    for _ <- 1..count//1, into: "" do
      Integer.to_string(Enum.random(0..9))
    end
  end
end
