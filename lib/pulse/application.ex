defmodule Pulse.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        PulseWeb.Telemetry,
        Pulse.Repo,
        {DNSCluster, query: Application.get_env(:pulse, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Pulse.PubSub},
        {AshAuthentication.Supervisor, otp_app: :pulse},
        Pulse.Core.Permissions,
        Pulse.Vault
      ] ++
        oban_children() ++
        [
          # Start to serve requests, typically the last entry
          PulseWeb.Endpoint
        ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Pulse.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Oban не запускается при выполнении миграций и сидов
  # (переменная OBAN_DISABLED=true), чтобы не обращаться к ещё не созданным таблицам.
  defp oban_children do
    if oban_disabled?() do
      []
    else
      [{Oban, Application.fetch_env!(:pulse, Oban)}]
    end
  end

  @doc """
  Отключён ли Oban.

  Используется миграциями и сидами: в этом режиме фоновые задачи
  не запускаются и не ставятся в очередь.
  """
  @spec oban_disabled?() :: boolean()
  def oban_disabled?, do: System.get_env("OBAN_DISABLED") in ["true", "1"]

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    PulseWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
