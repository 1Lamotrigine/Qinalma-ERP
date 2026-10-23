defmodule Pulse.Accounting.Changes.Unpost do
  @moduledoc """
  Изменение Ash: отмена проведения документа.

  Удаляет движения документа и возвращает статус `draft`. В закрытом
  периоде отмена запрещена — нужна корректировка или сторно.
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, opts, context) do
    rule = Keyword.fetch!(opts, :rule)

    Ash.Changeset.before_action(changeset, fn changeset ->
      case Pulse.Accounting.Posting.unpost(changeset.data, context.actor, rule) do
        {:ok, draft} ->
          Ash.Changeset.force_change_attribute(changeset, :status, draft.status)
          Ash.Changeset.force_change_attribute(changeset, :posted_at, nil)
          Ash.Changeset.force_change_attribute(changeset, :posted_by, nil)

        {:error, error} ->
          Ash.Changeset.add_error(changeset, error)
      end
    end)
  end
end
