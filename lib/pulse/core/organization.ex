defmodule Pulse.Core.Organization do
  @moduledoc """
  Организация — корень данных системы (tenant) и элемент справочника
  «Предприятие».

  Пользователь видит организации, в которых состоит
  (`OrganizationMembership`); активная организация выбирается в шапке
  и задаёт tenant для всех мультитенантных ресурсов.
  """
  use Ash.Resource,
    otp_app: :pulse,
    domain: Pulse.Core,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table("organizations")
    repo(Pulse.Repo)
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      accept([:name, :bin, :iin, :address, :phone])
      validate(present(:name))
    end

    update :update do
      accept([:name, :bin, :iin, :address, :phone])
    end
  end

  validations do
    validate(
      {Ash.Resource.Validation.Match,
       attribute: :bin, match: ~r/^\d{12}$/, message: "БИН должен содержать 12 цифр"},
      where: present(:bin)
    )

    validate(
      {Ash.Resource.Validation.Match,
       attribute: :iin, match: ~r/^\d{12}$/, message: "ИИН должен содержать 12 цифр"},
      where: present(:iin)
    )
  end

  policies do
    # Видит только организации, в которых состоит.
    policy action_type(:read) do
      authorize_if(Pulse.Core.Checks.MyOrganizations)
    end

    policy action_type([:create, :update, :destroy]) do
      authorize_if(Pulse.Core.Checks.RoleAllowed)
    end
  end

  attributes do
    uuid_primary_key(:id)

    attribute :name, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :bin, :string do
      allow_nil?(true)
      public?(true)
    end

    attribute :iin, :string do
      allow_nil?(true)
      public?(true)
    end

    attribute :address, :string do
      allow_nil?(true)
      public?(true)
    end

    attribute :phone, :string do
      allow_nil?(true)
      public?(true)
    end

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  relationships do
    has_many :memberships, Pulse.Core.OrganizationMembership do
      public?(true)
    end
  end

  identities do
    identity(:unique_bin, [:bin])
    identity(:unique_iin, [:iin])
  end
end
