defmodule PulseWeb.CSP do
  @moduledoc """
  Content-Security-Policy для браузерных страниц.

  Разрешает только собственные ресурсы и inline-стили (их использует
  LiveView и Tailwind). Скрипты — только свои и inline (нужны LiveView).
  """

  def header do
    [
      "default-src 'self'",
      "script-src 'self' 'unsafe-inline'",
      "style-src 'self' 'unsafe-inline'",
      "img-src 'self' data:",
      "font-src 'self' data:",
      "connect-src 'self' ws: wss:",
      "frame-ancestors 'none'",
      "base-uri 'self'",
      "form-action 'self'"
    ]
    |> Enum.join("; ")
  end
end
