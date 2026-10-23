defmodule PulseWeb.AuthController do
  @moduledoc """
  Контроллер для маршрутов аутентификации AshAuthentication (вход, выход,
  обновление токена, сброс пароля).
  """
  use PulseWeb, :controller
  use AshAuthentication.Phoenix.Controller

  def success(conn, _activity, user, _token) do
    return_to = get_session(conn, :return_to) || ~p"/"

    conn
    |> delete_session(:return_to)
    |> store_in_session(user)
    |> assign(:current_user, user)
    |> redirect(to: return_to)
  end

  def failure(conn, _activity, _reason) do
    conn
    |> put_flash(:error, "Неверный email или пароль")
    |> redirect(to: ~p"/sign-in")
  end

  def sign_out(conn, _params) do
    return_to = get_session(conn, :return_to) || ~p"/sign-in"

    conn
    |> clear_session(:pulse)
    |> redirect(to: return_to)
  end
end
