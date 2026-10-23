defmodule Pulse.Repo.Migrations.AddObanTables do
  @moduledoc """
  Таблицы Oban для фоновых задач.
  """
  use Ecto.Migration

  def up do
    Oban.Migration.up(version: 14)
  end

  def down do
    Oban.Migration.down(version: 1)
  end
end
