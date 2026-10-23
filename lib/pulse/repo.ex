defmodule Pulse.Repo do
  @moduledoc """
  Репозиторий Ecto для доступа к PostgreSQL.

  `migrate_extensions?` включает миграции расширений PostgreSQL, которые
  генерирует AshPostgres (например, `citext`, `pg_trgm`).
  """
  use AshPostgres.Repo, otp_app: :pulse

  @impl true
  def min_pg_version do
    %Version{major: 17, minor: 0, patch: 0}
  end

  @impl true
  def migrate_extensions?, do: true

  @impl true
  def installed_extensions do
    ["ash-functions", "citext", "pg_trgm"]
  end
end
