defmodule PulseWeb.ConnCase do
  @moduledoc """
  Тестовый кейс для проверок, которым нужен HTTP-соединение.

  Если тест работает с базой, включается SQL-sandbox.
  """
  use ExUnit.CaseTemplate

  using do
    quote do
      @endpoint PulseWeb.Endpoint

      use PulseWeb, :verified_routes

      import Plug.Conn
      import Phoenix.ConnTest
      import PulseWeb.ConnCase
    end
  end

  setup tags do
    Pulse.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  @doc """
  Логинит пользователя в тестовое соединение.
  """
  def log_in_user(conn, user) do
    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> AshAuthentication.Phoenix.Plug.store_in_session(user)
  end
end
