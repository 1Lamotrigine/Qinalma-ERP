import Config

# Подхватываем .env в dev/test, если файл есть. В проде переменные приходят
# из окружения (Docker env_file / секреты).
if config_env() != :prod do
  env_file = Path.expand("../.env", __DIR__)

  if File.exists?(env_file) do
    # Dotenvy.source!/1 возвращает разобранные значения, но не пишет их
    # в окружение процесса. Переносим их в System явно, чтобы config ниже
    # и код приложения видели те же переменные.
    env_file
    |> Dotenvy.source!()
    |> Enum.each(fn {key, value} -> System.put_env(key, value) end)
  end

  # Перечитываем параметры БД из окружения, чтобы значения из .env
  # перекрывали умолчания, заданные на этапе компиляции в dev.exs/test.exs.
  config :pulse, Pulse.Repo,
    username: System.get_env("DB_USER", "pulse"),
    password: System.get_env("DB_PASSWORD", "pulse"),
    hostname: System.get_env("DB_HOST", "127.0.0.1"),
    port: String.to_integer(System.get_env("DB_PORT", "5434"))
end

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/pulse start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") in ["true", "1"] do
  config :pulse, PulseWeb.Endpoint, server: true
end

config :pulse, PulseWeb.Endpoint, http: [port: String.to_integer(System.get_env("PORT", "4000"))]

# Секрет для токенов аутентификации Ash. В dev/test допускается значение по умолчанию.
config :pulse,
       :token_signing_secret,
       System.get_env("TOKEN_SIGNING_SECRET") || "dev-only-token-signing-secret-change-me-please"

if config_env() == :dev do
  # Reload browser tabs when matching files change.
  config :pulse, PulseWeb.Endpoint,
    live_reload: [
      web_console_logger: true,
      patterns: [
        # Static assets, except user uploads
        ~r"priv/static/(?!uploads/).*\.(js|css|png|jpeg|jpg|gif|svg)$"E,
        # Gettext translations
        ~r"priv/gettext/.*\.po$"E,
        # Router, Controllers, LiveViews and LiveComponents
        ~r"lib/pulse_web/router\.ex$"E,
        ~r"lib/pulse_web/(controllers|live|components)/.*\.(ex|heex)$"E
      ]
    ]
end

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      "ecto://#{System.get_env("DB_USER", "pulse")}:#{System.get_env("DB_PASSWORD", "pulse")}@#{System.get_env("DB_HOST", "localhost")}:#{System.get_env("DB_PORT", "5432")}/#{System.get_env("DB_NAME", "pulse_dev")}"

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :pulse, Pulse.Repo,
    # ssl: true,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
    socket_options: maybe_ipv6

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

  # Ключ шифрования персональных данных обязателен в проде: без него
  # ИИН и реквизиты не расшифровать, а стендовое значение небезопасно.
  cloak_key =
    System.get_env("CLOAK_KEY") ||
      raise """
      environment variable CLOAK_KEY is missing.
      Generate one with: mix run -e 'IO.puts(Base.encode64(:crypto.strong_rand_bytes(32)))'
      """

  if byte_size(cloak_key) < 32 do
    raise "CLOAK_KEY must be at least 32 bytes"
  end

  config :pulse, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :pulse, PulseWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://bandit.hexdocs.pm/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :pulse, PulseWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://plug.hexdocs.pm/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :pulse, PulseWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.
end
