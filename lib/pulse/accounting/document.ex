defmodule Pulse.Accounting.Document do
  @moduledoc """
  Общий каркас документа учёта (раздел 5.1 ТЗ).

  Даёт документу: сквозной номер по организации и году, дату, статус
  жизненного цикла (`draft → posted → cancelled`), поля проведения,
  валюту с курсом, оптимистичную блокировку и аудит.

  Действия `:post` и `:unpost` объявляет конкретный документ: они
  вызывают `Pulse.Accounting.Posting` и пишут движения в одной
  транзакции с записью статуса и аудита.
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

        attribute :number, :string do
          allow_nil?(true)
          public?(true)
        end

        attribute :doc_date, :date do
          allow_nil?(false)
          public?(true)
        end

        attribute :status, :atom do
          allow_nil?(false)
          default(:draft)
          constraints(one_of: [:draft, :posted, :cancelled])
          public?(true)
        end

        attribute :posted_at, :utc_datetime_usec do
          allow_nil?(true)
          public?(true)
        end

        attribute :posted_by, :uuid do
          allow_nil?(true)
          public?(true)
        end

        attribute :currency_id, :uuid do
          allow_nil?(true)
          public?(true)
        end

        attribute :rate, :decimal do
          allow_nil?(true)
          default(Decimal.new(1))
          public?(true)
        end

        attribute :comment, :string do
          allow_nil?(true)
          public?(true)
        end

        attribute :created_by, :uuid do
          allow_nil?(true)
          public?(true)
        end

        create_timestamp(:inserted_at)
        update_timestamp(:updated_at)
      end

      actions do
        defaults([:read])

        create :create do
          accept(
            unquote(opts[:create_accept] || [:doc_date, :number, :currency_id, :rate, :comment])
          )

          change(set_attribute(:created_by, actor(:id)))
          change(set_attribute(:status, :draft))
        end

        update :update do
          require_atomic?(false)

          accept(
            unquote(opts[:update_accept] || [:doc_date, :number, :currency_id, :rate, :comment])
          )

          validate(attribute_does_not_equal(:status, :posted),
            message: "проведённый документ нельзя изменить — сначала отмените проведение"
          )
        end

        destroy :destroy do
          primary?(true)
        end
      end
    end
  end
end
