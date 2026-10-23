defmodule Pulse.Tax.Invoice do
  @moduledoc """
  Счёт-фактура: выданный или полученный (раздел 5.5 ТЗ).

  Счёт-фактура формируется из документа-основания — реализации или
  поступления. Суммы НДС считаются по ставке на дату документа
  (`Pulse.Tax.Rates`), а не хранятся в коде.

  Выгрузка в XML и интеграция с ИС ЭСФ опираются на эти данные.
  """
  use Ash.Resource,
    otp_app: :pulse,
    domain: Pulse.Tax,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshPaperTrail.Resource]

  postgres do
    table("invoices")
    repo(Pulse.Repo)

    custom_indexes do
      index([:organization_id, :direction, :invoice_date],
        name: "invoices_journal_index"
      )

      index([:organization_id, :document_type, :document_id],
        name: "invoices_document_index"
      )
    end
  end

  multitenancy do
    strategy(:attribute)
    attribute(:organization_id)
  end

  paper_trail do
    change_tracking_mode(:changes_only)
    store_action_name?(true)
    attributes_as_attributes([:organization_id])
    reference_source?(false)
  end

  policies do
    policy action_type([:read, :create, :update, :destroy]) do
      authorize_if(Pulse.Core.Checks.RoleAllowed)
    end

    policy action_type([:update, :destroy]) do
      authorize_if(Pulse.Catalog.Checks.SameOrganization)
    end
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      accept([
        :direction,
        :number,
        :invoice_date,
        :counterparty_id,
        :contract_id,
        :document_type,
        :document_id,
        :amount,
        :vat_rate,
        :vat_amount,
        :currency_id,
        :note
      ])

      validate(present([:direction, :number, :invoice_date, :amount]))
      validate(one_of(:direction, [:issued, :received]))
    end

    update :update do
      accept([
        :number,
        :invoice_date,
        :counterparty_id,
        :contract_id,
        :amount,
        :vat_rate,
        :vat_amount,
        :note
      ])
    end
  end

  attributes do
    uuid_v7_primary_key(:id)

    attribute :organization_id, :uuid do
      allow_nil?(false)
      public?(true)
    end

    # Выданный (мы выставили) или полученный (нам выставили).
    attribute :direction, :atom do
      allow_nil?(false)
      constraints(one_of: [:issued, :received])
      public?(true)
    end

    attribute :number, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :invoice_date, :date do
      allow_nil?(false)
      public?(true)
    end

    attribute :counterparty_id, :uuid do
      allow_nil?(true)
      public?(true)
    end

    attribute :contract_id, :uuid do
      allow_nil?(true)
      public?(true)
    end

    # Документ-основание: реализация, поступление, платёжный документ.
    attribute :document_type, :string do
      allow_nil?(true)
      public?(true)
    end

    attribute :document_id, :uuid do
      allow_nil?(true)
      public?(true)
    end

    # Сумма с НДС.
    attribute :amount, :decimal do
      allow_nil?(false)
      public?(true)
    end

    # Ставка НДС в процентах на дату счёта-фактуры.
    attribute :vat_rate, :decimal do
      allow_nil?(true)
      public?(true)
    end

    attribute :vat_amount, :decimal do
      allow_nil?(true)
      public?(true)
    end

    attribute :currency_id, :uuid do
      allow_nil?(true)
      public?(true)
    end

    attribute :note, :string do
      allow_nil?(true)
      public?(true)
    end

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  relationships do
    belongs_to :counterparty, Pulse.Catalog.Counterparty do
      define_attribute?(false)
      public?(true)
    end
  end

  @doc """
  Сумма без НДС по сумме с НДС и ставке в процентах.
  """
  @spec net_amount(Decimal.t(), Decimal.t() | nil) :: Decimal.t()
  def net_amount(amount, nil), do: amount

  def net_amount(amount, vat_rate) do
    amount
    |> Decimal.div(Decimal.add(1, Decimal.div(vat_rate, 100)))
    |> Decimal.round(2)
  end

  @doc """
  Сумма НДС по сумме с НДС и ставке в процентах.
  """
  @spec vat_amount(Decimal.t(), Decimal.t() | nil) :: Decimal.t()
  def vat_amount(_amount, nil), do: Decimal.new(0)

  def vat_amount(amount, vat_rate) do
    Decimal.sub(amount, net_amount(amount, vat_rate))
  end
end
