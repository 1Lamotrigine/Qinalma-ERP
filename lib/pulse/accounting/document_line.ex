defmodule Pulse.Accounting.DocumentLine do
  @moduledoc """
  Общий каркас строки табличной части документа.

  Строки — дочерние ресурсы со сквозным `line_no` и ссылкой на
  документ. Строку нельзя менять у проведённого документа: правку
  блокирует документ-владелец.
  """
  defmacro __using__(opts) do
    quote do
      use Ash.Resource,
        otp_app: :pulse,
        domain: unquote(opts[:domain]),
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
        policy action_type([:read, :create, :update, :destroy]) do
          authorize_if(Pulse.Core.Checks.RoleAllowed)
        end
      end

      attributes do
        uuid_v7_primary_key(:id)

        attribute :organization_id, :uuid do
          allow_nil?(false)
          public?(true)
        end

        attribute :line_no, :integer do
          allow_nil?(false)
          public?(true)
        end

        # Ссылка на документ-владелец: явный атрибут, чтобы строку можно
        # было создать и связать по идентификатору.
        attribute :document_id, :uuid do
          allow_nil?(false)
          public?(true)
        end

        attribute :quantity, :decimal do
          allow_nil?(false)
          default(Decimal.new(1))
          public?(true)
        end

        attribute :price, :decimal do
          allow_nil?(false)
          default(Decimal.new(0))
          public?(true)
        end

        attribute :amount, :decimal do
          allow_nil?(false)
          default(Decimal.new(0))
          public?(true)
        end

        create_timestamp(:inserted_at)
        update_timestamp(:updated_at)
      end

      actions do
        defaults([:read, :destroy])

        create :create do
          accept(
            unquote(
              opts[:create_accept] ||
                [
                  :organization_id,
                  :document_id,
                  :line_no,
                  :nomenclature_id,
                  :quantity,
                  :price,
                  :amount
                ]
            )
          )
        end

        update :update do
          accept(unquote(opts[:update_accept] || [:quantity, :price, :amount]))
        end
      end
    end
  end
end
