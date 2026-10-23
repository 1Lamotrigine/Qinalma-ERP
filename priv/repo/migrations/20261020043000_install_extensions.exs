defmodule Pulse.Repo.Migrations.InstallExtensions do
  @moduledoc """
  Устанавливает расширения PostgreSQL, нужные AshPostgres.

  `citext` — регистронезависимый текст (email пользователей).
  `pg_trgm` — нечёткий поиск (глобальный поиск, этап 1).
  """
  use Ecto.Migration

  def up do
    execute("CREATE EXTENSION IF NOT EXISTS citext")
    execute("CREATE EXTENSION IF NOT EXISTS pg_trgm")
  end

  def down do
    execute("DROP EXTENSION IF EXISTS pg_trgm")
    execute("DROP EXTENSION IF EXISTS citext")
  end
end
