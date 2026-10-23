defmodule Pulse.Accounts.UserTest do
  @moduledoc """
  Проверки регистрации и входа пользователя.
  """
  use Pulse.DataCase, async: true

  alias Pulse.Accounts
  alias Pulse.Accounts.User

  describe "register_with_password" do
    test "создаёт пользователя с email и паролем" do
      assert {:ok, %User{} = user} =
               Ash.create(
                 User,
                 %{
                   email: "ivan@qinalma.local",
                   password: "secret123456",
                   password_confirmation: "secret123456"
                 },
                 action: :register_with_password,
                 domain: Accounts
               )

      assert to_string(user.email) == "ivan@qinalma.local"
      assert user.hashed_password
      refute user.hashed_password == "secret123456"
    end

    test "не создаёт пользователя, если пароли не совпадают" do
      assert {:error, _} =
               Ash.create(
                 User,
                 %{
                   email: "petr@qinalma.local",
                   password: "secret123456",
                   password_confirmation: "другой_пароль"
                 },
                 action: :register_with_password,
                 domain: Accounts
               )
    end

    test "email уникален без учёта регистра" do
      user = Pulse.Factory.create_user(%{email: "anna@qinalma.local"})
      assert to_string(user.email) == "anna@qinalma.local"

      assert {:error, _} =
               Ash.create(
                 User,
                 %{
                   email: "ANNA@qinalma.local",
                   password: "secret123456",
                   password_confirmation: "secret123456"
                 },
                 action: :register_with_password,
                 domain: Accounts
               )
    end
  end

  describe "вход" do
    test "вход возвращает пользователя для верных данных" do
      Pulse.Factory.create_user(%{email: "login@qinalma.local", password: "secret123456"})

      strategy = AshAuthentication.Info.strategy!(User, :password)

      assert {:ok, user} =
               AshAuthentication.Strategy.Password.Actions.sign_in(
                 strategy,
                 %{email: "login@qinalma.local", password: "secret123456"},
                 domain: Accounts
               )

      assert to_string(user.email) == "login@qinalma.local"
    end

    test "токен сессии создаётся и проверяется" do
      user = Pulse.Factory.create_user(%{email: "token@qinalma.local"})

      assert {:ok, token, _claims} = AshAuthentication.Jwt.token_for_user(user)
      assert {:ok, _claims, _resource} = AshAuthentication.Jwt.verify(token, User)
    end

    test "вход не проходит с неверным паролем" do
      Pulse.Factory.create_user(%{email: "wrong@qinalma.local", password: "secret123456"})

      strategy = AshAuthentication.Info.strategy!(User, :password)

      assert {:error, _} =
               AshAuthentication.Strategy.Password.Actions.sign_in(
                 strategy,
                 %{email: "wrong@qinalma.local", password: "неверный_пароль"},
                 domain: Accounts
               )
    end
  end
end
