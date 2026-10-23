# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :pulse,
  ecto_repos: [Pulse.Repo],
  generators: [timestamp_type: :utc_datetime],
  ash_domains: [
    Pulse.Accounts,
    Pulse.Core,
    Pulse.Catalog,
    Pulse.Ledger,
    Pulse.Accounting,
    Pulse.Purchasing,
    Pulse.Sales,
    Pulse.Treasury,
    Pulse.Tax,
    Pulse.HR,
    Pulse.Payroll
  ]

# Аш и AshPhoenix
config :ash, :use_all_identities_in_manage_relationship?, false
config :ash, default_string_length_count: :codepoints

# AshAuthentication.Phoenix: пути входа и общий layout
config :ash_authentication_phoenix,
  layout: {PulseWeb.Layouts, :root},
  sign_in_route: "/sign-in",
  reset_route: "/reset"

# Configure the endpoint
config :pulse, PulseWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: PulseWeb.ErrorHTML, json: PulseWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Pulse.PubSub,
  live_view: [signing_salt: "vnUTl1qQ"]

# Configure LiveView
config :phoenix_live_view,
  # the attribute set on all root tags. Used for Phoenix.LiveView.ColocatedCSS.
  root_tag_attribute: "phx-r"

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  pulse: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.3.3",
  pulse: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Локализация ru: числа, даты, валюта
config :ex_cldr,
  default_locale: "ru",
  default_backend: Pulse.Cldr

config :ex_cldr_numbers,
  default_locale: "ru",
  default_backend: Pulse.Cldr

# Фоновые задачи (Oban)
config :pulse, Oban,
  engine: Oban.Engines.Basic,
  notifier: Oban.Notifiers.Postgres,
  repo: Pulse.Repo,
  plugins: [Oban.Plugins.Pruner, {Oban.Plugins.Cron, crontab: []}],
  queues: [default: 10]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
