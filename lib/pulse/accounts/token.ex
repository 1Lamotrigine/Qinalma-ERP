defmodule Pulse.Accounts.Token do
  @moduledoc """
  Токены аутентификации: отзыв, подтверждение, сброс пароля.

  Расширение `AshAuthentication.TokenResource` само создаёт нужные атрибуты
  и действия, поэтому здесь только подключение и таблица.
  """
  use Ash.Resource,
    otp_app: :pulse,
    domain: Pulse.Accounts,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAuthentication.TokenResource]

  postgres do
    table("tokens")
    repo(Pulse.Repo)
  end
end
