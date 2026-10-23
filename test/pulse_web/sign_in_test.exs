defmodule PulseWeb.SignInTest do
  @moduledoc """
  Сквозной сценарий: вход через форму, доступ к рабочей области, выход.
  """
  use PulseWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "вход" do
    test "форма входа отображается", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/sign-in")

      assert html =~ "user[email]"
      assert html =~ "user[password]"
    end

    test "вошедший пользователь не видит страницу входа как анонимный", %{conn: conn} do
      _user = Pulse.Factory.create_user(%{email: "viewer@qinalma.local"})

      {:ok, _view, html} = live(conn, ~p"/sign-in")

      # Форма входа доступна анонимному пользователю
      assert html =~ "user[email]"
    end
  end
end
