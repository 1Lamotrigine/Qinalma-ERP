defmodule Pulse.Ledger.Resource do
  @moduledoc """
  Общий каркас регистра накопления: движения, которые только добавляются.

  Регистр — это мультитенантный ресурс без действий `update`/`destroy`:
  движения меняются исключительно вместе с документом-регистратором
  (проведение создаёт, отмена удаляет). Разрешение на удаление даётся
  отдельным действию `:purge`, которое документ вызывает в своей
  транзакции.
  """
  defmacro __using__(opts) do
    quote do
      use Ash.Resource,
        otp_app: :pulse,
        domain: unquote(opts[:domain] || Pulse.Ledger),
        data_layer: AshPostgres.DataLayer,
        authorizers: [Ash.Policy.Authorizer]

      postgres do
        table(unquote(opts[:table]))
        repo(Pulse.Repo)
      end

      multitenancy do
        strategy(:attribute)
        attribute(:organization_id)
      end

      policies do
        # Читают и проводят документы — по матрице прав на ресурс движения.
        policy action_type([:read, :create, :destroy]) do
          authorize_if(Pulse.Core.Checks.RoleAllowed)
        end

        policy action_type(:destroy) do
          authorize_if(Pulse.Ledger.Checks.SameOrganization)
        end
      end

      attributes do
        uuid_primary_key(:id)

        attribute :organization_id, :uuid do
          allow_nil?(false)
          public?(true)
        end

        # Документ-регистратор и его строка: движения создаются проведением.
        attribute :document_type, :string do
          allow_nil?(false)
          public?(true)
        end

        attribute :document_id, :uuid do
          allow_nil?(false)
          public?(true)
        end

        attribute :document_line_id, :uuid do
          allow_nil?(true)
          public?(true)
        end

        create_timestamp(:inserted_at)
        update_timestamp(:updated_at)
      end

      actions do
        default_accept([:organization_id])
        defaults([:read])

        # Удаление движений при отмене проведения.
        destroy :purge do
          primary?(false)
          accept([])
          require_atomic?(false)
        end
      end
    end
  end
end
