defmodule Pulse.Core.Checks.RoleAllowed do
  @moduledoc """
  Проверка Ash-политик: действие роли на ресурс разрешено матрицей прав.

  Ключ ресурса выводится из модуля ресурса: `Pulse.Catalog.Counterparty`
  → `catalog.counterparty`. Действие берётся из запускаемого action
  (`:read`, `:create`, `:update`, `:destroy`).

  Читает кэш `Pulse.Core.Permissions`; администратор разрешён всегда.
  """
  use Ash.Policy.SimpleCheck

  # Модули, чей ключ в матрице отличается от автоматического вывода.
  @overrides %{
    Pulse.Core.OrganizationMembership => "core.membership",
    Pulse.Core.RolePermission => "core.role_permission",
    Pulse.Core.PeriodLock => "core.period_lock"
  }

  @impl true
  def match?(%{role: role}, context, _opts) do
    {:ok,
     Pulse.Core.Permissions.allowed?(
       role,
       resource_key(context.resource),
       to_string(context.action.name)
     )}
  end

  def match?(_actor, _context, _opts), do: {:ok, false}

  @impl true
  def describe(_opts), do: "роль пользователя разрешает это действие по матрице прав"

  @doc """
  Ключ ресурса в матрице: `Module` → `"domain.resource"` (без префикса Pulse).
  """
  @spec resource_key(module()) :: String.t()
  def resource_key(module) do
    Map.get_lazy(@overrides, module, fn ->
      module
      |> Module.split()
      |> Enum.drop_while(&(&1 != "Pulse"))
      |> Enum.drop(1)
      |> Enum.map_join(".", &String.downcase/1)
    end)
  end
end
