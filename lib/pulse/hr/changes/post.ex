defmodule Pulse.HR.Changes.Post do
  @moduledoc """
  Изменение Ash: проведение кадрового документа.

  Вызывает `Pulse.HR.Posting.post/2`: карточка сотрудника меняется и
  статус документа переходит в «проведён» в одной транзакции.
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, opts, context) do
    rule = Keyword.fetch!(opts, :rule)

    Ash.Changeset.before_action(changeset, fn changeset ->
      document = changeset.data
      actor = context.actor

      case Pulse.HR.Posting.post(document, actor) do
        {:ok, posted} ->
          Ash.Changeset.force_change_attribute(changeset, :status, posted.status)
          Ash.Changeset.force_change_attribute(changeset, :posted_at, posted.posted_at)
          Ash.Changeset.force_change_attribute(changeset, :posted_by, posted.posted_by)
          _ = rule

        {:error, error} ->
          Ash.Changeset.add_error(changeset, error)
      end
    end)
  end
end
