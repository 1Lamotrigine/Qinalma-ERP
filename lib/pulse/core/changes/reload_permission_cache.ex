defmodule Pulse.Core.Changes.ReloadPermissionCache do
  @moduledoc """
  Перезагружает кэш матрицы прав после изменения `RolePermission`.
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, result ->
      Pulse.Core.Permissions.reload()
      {:ok, result}
    end)
  end
end
