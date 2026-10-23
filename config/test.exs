import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :pulse, Pulse.Repo,
  username: System.get_env("DB_USER", "pulse"),
  password: System.get_env("DB_PASSWORD", "pulse"),
  hostname: System.get_env("DB_HOST", "127.0.0.1"),
  port: String.to_integer(System.get_env("DB_PORT", "5434")),
  database: "pulse_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :pulse, PulseWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "TyxrxiuTRJ1RziDPO7LBiR/gw4ZwiRv2sXZM4zfRdZ6Dlpl5YlOI9C6yaoRRrIVW",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Oban не запускается в тестах: очереди проверяются отдельно.
config :pulse, Oban, testing: :manual

# Кэш матрицы прав отключён: проверка идёт в БД (sandbox-транзакции тестов
# не видны отдельному ETS-процессу).
config :pulse, cache_permissions: false

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
