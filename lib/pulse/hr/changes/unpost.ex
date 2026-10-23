defmodule Pulse.HR.Changes.Unpost do
  @moduledoc """
  Изменение Ash: отмена проведения кадрового документа.

  Возвращает карточку сотрудника к снимку и статус документа в «черновик».
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, opts, context) do
    rule = Keyword.fetch!(opts, :rule)

    Ash.Changeset.before_action(changeset, fn changeset ->
      document = changeset.data
      actor = context.actor

      case Pulse.HR.Posting.unpost(document, actor, rule) do
        {:ok, draft} ->
          Ash.Changeset.force_change_attribute(changeset, :status, draft.status)
          Ash.Changeset.force_change_attribute(changeset, :posted_at, draft.posted_at)
          Ash.Changeset.force_change_attribute(changeset, :posted_by, draft.posted_by)

        {:error, error} ->
          Ash.Changeset.add_error(changeset, error)
      end
    end)
  end
end
