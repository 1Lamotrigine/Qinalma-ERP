defmodule PulseWeb.LiveUserAuth do
  @moduledoc """
  Хуки `on_mount` для LiveView: загрузка текущего пользователя и защита маршрутов.

  `:live_user_required` не пускает анонимных пользователей в рабочую область.
  `:live_user_optional` загружает пользователя, если он вошёл.
  """
  import Phoenix.LiveView
  import Phoenix.Component, only: [assign: 3]

  def on_mount(:live_user_required, _params, session, socket) do
    case load_user(session) do
      {:ok, user} ->
        {:cont, assign(socket, :current_user, user)}

      :error ->
        {:halt, redirect(socket, to: "/sign-in")}
    end
  end

  def on_mount(:live_user_optional, _params, session, socket) do
    case load_user(session) do
      {:ok, user} -> {:cont, assign(socket, :current_user, user)}
      :error -> {:cont, socket}
    end
  end

  defp load_user(%{"user_token" => token}) when is_binary(token) do
    case AshAuthentication.Jwt.verify(token, Pulse.Accounts.User) do
      {:ok, claims, _resource} ->
        with {:ok, %{"sub" => subject}} <- {:ok, claims},
             {:ok, user} <- fetch_user(subject) do
          {:ok, user}
        else
          _ -> :error
        end

      _ ->
        :error
    end
  end

  defp load_user(_session), do: :error

  defp fetch_user(subject) do
    case AshAuthentication.subject_to_user(subject, Pulse.Accounts.User) do
      {:ok, user} -> {:ok, user}
      _ -> :error
    end
  end
end
