defmodule PulseWeb.Components.Combobox do
  @moduledoc """
  Выпадающий список для ссылочных полей.

  Пока — обычный `select` со списком опций. Живой поиск и асинхронная
  подгрузка добавляются, когда появятся справочники (этап 2).
  """
  use PulseWeb, :html

  attr :name, :string, required: true
  attr :id, :string, required: true
  attr :options, :list, required: true
  attr :value, :any, default: nil
  attr :target, :any, default: nil
  attr :change_event, :string, default: nil

  def combobox(assigns) do
    ~H"""
    <select
      class="f"
      id={@id}
      name={@name}
      phx-change={@change_event}
      phx-target={@target}
    >
      <option
        :for={opt <- @options}
        value={opt_value(opt)}
        selected={opt_value(opt) == to_string(@value)}
      >
        {opt_label(opt)}
      </option>
    </select>
    """
  end

  defp opt_value(%{value: value}), do: to_string(value)
  defp opt_value({value, _label}), do: to_string(value)
  defp opt_value(value) when is_binary(value), do: value
  defp opt_value(value), do: to_string(value)

  defp opt_label(%{label: label}), do: label
  defp opt_label({_value, label}), do: label
  defp opt_label(value) when is_binary(value), do: value
  defp opt_label(value), do: to_string(value)
end
