defmodule Pulse.Accounts.Secrets do
  @moduledoc """
  Секрет для подписи токенов аутентификации.

  Значение берётся из переменной окружения `TOKEN_SIGNING_SECRET`
  (см. `config/runtime.exs`).
  """
  use AshAuthentication.Secret

  @impl AshAuthentication.Secret
  def secret_for(
        [:authentication, :tokens, :signing_secret],
        _resource,
        _opts,
        _context
      ) do
    Application.fetch_env(:pulse, :token_signing_secret)
  end
end
