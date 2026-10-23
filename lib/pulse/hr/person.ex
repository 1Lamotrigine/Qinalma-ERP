defmodule Pulse.HR.Person do
  @moduledoc """
  Физическое лицо (раздел 5.5, 7 ТЗ).

  Физлицо — учётная единица человека независимо от того, работает он
  в организации или нет: сотрудник ссылается на физлицо. Персональные
  данные (ИИН, удостоверяющий документ) хранятся в колонках, зашифрованных
  `Pulse.Types.Encrypted`.
  """
  use Pulse.HR.Resource, table: "hr_people"

  actions do
    defaults([:read, :destroy])

    create :create do
      accept([
        :last_name,
        :first_name,
        :middle_name,
        :iin,
        :birth_date,
        :identity_document,
        :address,
        :phone
      ])

      validate(present([:last_name, :first_name]))
    end

    update :update do
      accept([
        :last_name,
        :first_name,
        :middle_name,
        :iin,
        :birth_date,
        :identity_document,
        :address,
        :phone
      ])
    end
  end

  attributes do
    attribute :last_name, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :first_name, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :middle_name, :string do
      allow_nil?(true)
      public?(true)
    end

    # ИИН — персональные данные: в базе хранится зашифрованным.
    attribute :iin, Pulse.Types.Encrypted do
      allow_nil?(true)
      public?(true)
    end

    attribute :birth_date, :date do
      allow_nil?(true)
      public?(true)
    end

    # Удостоверяющий документ (номер и кем выдан) — тоже персональные данные.
    attribute :identity_document, Pulse.Types.Encrypted do
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
  end

  relationships do
    has_many :employees, Pulse.HR.Employee do
      destination_attribute(:person_id)
      public?(true)
    end
  end

  @doc """
  Полное имя: фамилия, имя и отчество.
  """
  @spec full_name(t()) :: String.t()
  def full_name(person) do
    [person.last_name, person.first_name, person.middle_name]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end
end
