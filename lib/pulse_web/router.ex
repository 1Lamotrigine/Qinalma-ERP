defmodule PulseWeb.Router do
  use PulseWeb, :router
  use AshAuthentication.Phoenix.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {PulseWeb.Layouts, :root}
    plug :protect_from_forgery

    plug :put_secure_browser_headers, %{
      "content-security-policy" => PulseWeb.CSP.header()
    }

    plug :load_from_session
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug :load_from_bearer
  end

  scope "/", PulseWeb do
    pipe_through :browser

    ash_authentication_live_session :authenticated_routes,
      on_mount: [{PulseWeb.LiveUserAuth, :live_user_required}] do
      live "/", WorkspaceLive, :index
    end
  end

  scope "/", PulseWeb do
    pipe_through :browser

    sign_in_route(register_path: "/register", reset_path: "/reset", auth_routes_prefix: "/auth")
    sign_out_route(AuthController)
    auth_routes(AuthController, Pulse.Accounts.User)
    reset_route(auth_routes_prefix: "/auth")

    get "/invoices/:id/xml", InvoiceController, :xml
  end

  # Enable LiveDashboard in development
  if Application.compile_env(:pulse, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: PulseWeb.Telemetry
    end
  end
end
