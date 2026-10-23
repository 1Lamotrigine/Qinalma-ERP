defmodule Pulse.Accounts.User do
  @moduledoc """
  Пользователь системы.

  Аутентификация по email и паролю. Роли и членство в организациях
  добавляются на этапе 2.
  """
  use Ash.Resource,
    otp_app: :pulse,
    domain: Pulse.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshAuthentication]

  authentication do
    domain(Pulse.Accounts)

    strategies do
      password :password do
        identity_field(:email)

        resettable do
          sender(Pulse.Accounts.User.Senders.SendPasswordResetEmail)
        end
      end
    end

    tokens do
      enabled?(true)
      token_resource(Pulse.Accounts.Token)
      signing_secret(Pulse.Accounts.Secrets)
      store_all_tokens?(true)
      require_token_presence_for_authentication?(true)
    end
  end

  postgres do
    table("users")
    repo(Pulse.Repo)
  end

  actions do
    defaults([:read, :destroy])

    create :register_with_password do
      description("Регистрация пользователя с email и паролем")
      accept([:email])

      argument(:password, :string, allow_nil?: false, sensitive?: true)
      argument(:password_confirmation, :string, allow_nil?: false, sensitive?: true)

      change(AshAuthentication.Strategy.Password.HashPasswordChange)
      change(AshAuthentication.GenerateTokenChange)

      validate(AshAuthentication.Strategy.Password.PasswordConfirmationValidation)

      change(set_attribute(:created_by, "system"))
    end

    read :get_by_email do
      description("Найти пользователя по email")
      get?(true)
      argument(:email, :ci_string, allow_nil?: false)
      filter(expr(email == ^arg(:email)))
    end

    read :get_by_id do
      description("Найти пользователя по идентификатору")
      get?(true)
      argument(:id, :uuid, allow_nil?: false)
      filter(expr(id == ^arg(:id)))
    end
  end

  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if(always())
    end

    policy action_type(:read) do
      authorize_if(expr(id == ^actor(:id)))
    end

    policy action_type(:create) do
      authorize_if(always())
    end
  end

  attributes do
    uuid_primary_key(:id)

    attribute :email, :ci_string do
      allow_nil?(false)
      public?(true)
    end

    attribute :hashed_password, :string do
      allow_nil?(false)
      sensitive?(true)
    end

    attribute :created_by, :string do
      allow_nil?(true)
      default("system")
    end

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  identities do
    identity(:unique_email, [:email])
  end
end
