defmodule Pulse.Catalog.Counterparty do
  @moduledoc """
  Контрагент: организация или физическое лицо.

  ИНН (ИИН) и БИН проверяются на формат Казахстана — 12 цифр.
  """
  use Pulse.Catalog.Resource, table: "counterparties"

  actions do
    create :create do
      accept([:name, :kind, :bin, :iin, :address, :phone, :email, :comment])
      validate(present([:name, :kind]))
    end

    update :update do
      accept([:name, :kind, :bin, :iin, :address, :phone, :email, :comment])
      require_atomic?(false)
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

  attributes do
    attribute :name, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :kind, :atom do
      allow_nil?(false)
      constraints(one_of: [:legal, :individual])
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

    attribute :email, :string do
      allow_nil?(true)
      public?(true)
    end

    attribute :comment, :string do
      allow_nil?(true)
      public?(true)
    end
  end

  relationships do
    has_many :contracts, Pulse.Catalog.Contract do
      public?(true)
    end
  end

  identities do
    identity(:unique_bin, [:bin])
  end
end
