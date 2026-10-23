defmodule Pulse.Catalog.Resource do
  @moduledoc """
  Общий каркас справочника домена `Pulse.Catalog`.

  Подключает AshPostgres, атрибутную мультитенантность по
  `organization_id`, аудит AshPaperTrail и типовую политику
  «роль × действие» из матрицы прав.
  """
  defmacro __using__(opts) do
    quote do
      use Ash.Resource,
        otp_app: :pulse,
        domain: unquote(opts[:domain] || Pulse.Catalog),
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

        # organization_id — тенант-атрибут: он должен быть настоящим
        # атрибутом версии, а не частью changes (требование multitenancy).
        attributes_as_attributes([:organization_id])

        # Версии переживают удаление записи: без внешнего ключа история
        # остаётся, даже когда сам элемент справочника удалён.
        reference_source?(false)
      end

      policies do
        policy action_type([:read, :create, :update, :destroy]) do
          authorize_if(Pulse.Core.Checks.RoleAllowed)
        end

        # Изменять и удалять можно только записи активной организации.
        policy action_type([:update, :destroy]) do
          authorize_if(Pulse.Catalog.Checks.SameOrganization)
        end
      end

      attributes do
        uuid_primary_key(:id)

        attribute :organization_id, :uuid do
          allow_nil?(false)
          public?(true)
        end

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
