defmodule Pulse.Accounting.Changes.Post do
  @moduledoc """
  Изменение Ash: проведение документа.

  Вызывает `Pulse.Accounting.Posting.post/3`, который формирует
  движения и меняет статус в одной транзакции.
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, opts, context) do
    rule = Keyword.fetch!(opts, :rule)

    Ash.Changeset.before_action(changeset, fn changeset ->
      document = changeset.data
      actor = context.actor

      case Pulse.Accounting.Posting.post(document, actor, rule) do
        {:ok, posted} ->
          Ash.Changeset.force_change_attribute(changeset, :status, posted.status)
          Ash.Changeset.force_change_attribute(changeset, :posted_at, posted.posted_at)
          Ash.Changeset.force_change_attribute(changeset, :posted_by, posted.posted_by)

        {:error, error} ->
          Ash.Changeset.add_error(changeset, error)
      end
    end)
  end
end
