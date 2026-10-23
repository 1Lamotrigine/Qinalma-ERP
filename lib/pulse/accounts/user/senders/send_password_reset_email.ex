defmodule Pulse.Accounts.User.Senders.SendPasswordResetEmail do
  @moduledoc """
  Отправка письма для сброса пароля.

  На этапе 0 почта не настроена, письмо выводится в лог. Реальная отправка
  подключается вместе с почтовым сервисом.
  """
  use AshAuthentication.Sender

  require Logger

  @impl AshAuthentication.Sender
  def send(user, token, _opts) do
    Logger.info("""
    Письмо для сброса пароля
    пользователь: #{user.email}
    токен: #{token}
    """)
  end
end
