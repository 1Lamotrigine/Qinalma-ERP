defmodule PulseWeb.Components.HubComponent do
  @moduledoc """
  Хаб раздела: группы пунктов меню с фильтром и отметкой избранного.

  Нереализованные пункты показываются серыми с пометкой «в разработке»
  и не ведут на заглушку.
  """
  use PulseWeb, :html

  attr :section, :map, required: true
  attr :favorites, :any, required: true, doc: "MapSet идентификаторов избранного"
  attr :filter, :string, default: ""

  def hub(assigns) do
    assigns = assign(assigns, :groups, filtered_groups(assigns.section, assigns.filter))

    ~H"""
    <div class="hubh">
      <span class="ic" style={icon_style(@section.hue)}>{@section.short}</span>
      <div>
        <h1>{@section.title}</h1>
      </div>
      <input
        id="hub-filter"
        placeholder="Фильтр по разделу"
        value={@filter}
        phx-keyup="filter-hub"
        phx-debounce="120"
      />
    </div>

    <div class="hub" id="hub-groups">
      <section :for={{group, items} <- @groups} class="grp">
        <h2>{group.title}</h2>
        <div :for={item <- items} style="display: flex">
          <button
            class={["lk", item.primary && "b", !item.implemented && "dim"]}
            phx-click={item.implemented && "open-item"}
            phx-value-section={@section.id}
            phx-value-group={group.title}
            phx-value-title={item.title}
            disabled={!item.implemented}
          >
            {item.title}
          </button>
          <span :if={!item.implemented} class="badge-dev">в разработке</span>
          <button
            :if={item.implemented}
            class={["st", favorite?(@favorites, @section.id, item.title) && "on"]}
            phx-click="toggle-favorite"
            phx-value-section={@section.id}
            phx-value-title={item.title}
            title="В избранное"
          >
            ★
          </button>
        </div>
      </section>
    </div>
    """
  end

  defp filtered_groups(section, filter) do
    filter = String.downcase(String.trim(filter || ""))

    section.groups
    |> Enum.map(fn group ->
      items =
        Enum.filter(group.items, fn item ->
          filter == "" or String.contains?(String.downcase(item.title), filter)
        end)

      {group, items}
    end)
    |> Enum.reject(fn {_group, items} -> items == [] end)
  end

  defp favorite?(favorites, section_id, title) do
    MapSet.member?(favorites, "#{section_id}|#{title}")
  end

  defp icon_style(hue), do: PulseWeb.DesignTokens.section_icon_style(hue)
end
