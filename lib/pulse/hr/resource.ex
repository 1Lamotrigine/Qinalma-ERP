defmodule Pulse.HR.Resource do
  @moduledoc """
  Общий каркас справочного ресурса кадрового учёта.

  Ресурсы кадров мультитенантны по `organization_id` и аудируются
  AshPaperTrail: изменения приказов и карточек сотрудников должны быть
  прослеживаемы (раздел 7 ТЗ).
  """
  defmacro __using__(opts) do
    quote do
      use Ash.Resource,
        otp_app: :pulse,
        domain: Pulse.HR,
        data_layer: AshPostgres.DataLayer,
        authorizers: [Ash.Policy.Authorizer],
        extensions: [AshPaperTrail.Resource]

      postgres do
        table(unquote(opts[:table]))
        repo(Pulse.Repo)
      end

      multitenancy do
        strategy(:attribute)
        attribute(:organization_id)
      end

      paper_trail do
        change_tracking_mode(:changes_only)
        store_action_name?(true)
        attributes_as_attributes([:organization_id])
        reference_source?(false)
      end

      policies do
        policy action_type([:read, :create, :update, :destroy]) do
          authorize_if(Pulse.Core.Checks.RoleAllowed)
        end

        policy action_type([:update, :destroy]) do
          authorize_if(Pulse.Catalog.Checks.SameOrganization)
        end
      end

      attributes do
        uuid_v7_primary_key(:id)

        attribute :organization_id, :uuid do
          allow_nil?(false)
          public?(true)
        end

        create_timestamp(:inserted_at)
        update_timestamp(:updated_at)
      end
    end
  end
end
