defmodule Pulse.Accounting.Resource do
  @moduledoc """
  Общий каркас учётного объекта домена `Pulse.Accounting`.

  План счетов и субконто — общие для инсталляции (не мультитенантные):
  это законодательные справочники, одинаковые для всех организаций.
  Так же, как `Pulse.Core.RolePermission`, они защищены политикой
  «роль × действие» и аудируются AshPaperTrail.
  """
  defmacro __using__(opts) do
    quote do
      use Ash.Resource,
        otp_app: :pulse,
        domain: unquote(opts[:domain]),
        data_layer: AshPostgres.DataLayer,
        authorizers: [Ash.Policy.Authorizer],
        extensions: [AshPaperTrail.Resource]

      postgres do
        table(unquote(opts[:table]))
        repo(Pulse.Repo)
      end

      paper_trail do
        change_tracking_mode(:changes_only)
        store_action_name?(true)
        reference_source?(false)
      end

      policies do
        policy action_type([:read, :create, :update, :destroy]) do
          authorize_if(Pulse.Core.Checks.RoleAllowed)
        end
      end

      attributes do
        uuid_primary_key(:id)
        create_timestamp(:inserted_at)
        update_timestamp(:updated_at)
      end

      actions do
        defaults([:read])

        destroy :destroy do
          primary?(true)
        end
      end
    end
  end
end
