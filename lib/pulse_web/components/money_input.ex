defmodule PulseWeb.Components.MoneyInput do
  @moduledoc """
  Ввод денежной суммы.

  Сумма хранится как `Decimal`, отображается с разделителями разрядов
  и пробелом перед валютой. Валюта по умолчанию — KZT.
  """
  use PulseWeb, :html

  attr :value, :any, default: nil
  attr :name, :string, required: true
  attr :id, :string, required: true
  attr :currency, :string, default: "KZT"
  attr :target, :any, default: nil
  attr :change_event, :string, default: nil

  def money_input(assigns) do
    ~H"""
    <div class="n">
      <input
        class="f"
        type="text"
        inputmode="decimal"
        id={@id}
        name={@name}
        value={format_money(@value)}
        phx-change={@change_event}
        phx-target={@target}
        style="text-align: right"
      />
      <small class="sub">{@currency}</small>
    </div>
    """
  end

  @doc """
  Форматирует сумму с разделителями разрядов: `1 757 790,00`.
  """
  def format_money(nil), do: ""

  def format_money(%Decimal{} = value) do
    value
    |> Decimal.round(2)
    |> Decimal.to_string(:normal)
    |> format_grouped()
  end

  def format_money(value) when is_number(value), do: format_money(Decimal.new(value))
  def format_money(value) when is_binary(value), do: value

  defp format_grouped(string) do
    [int | rest] = String.split(string, ".")

    grouped =
      int
      |> String.reverse()
      |> String.replace(~r/(\d{3})(?=\d)/, "\\1 ")
      |> String.reverse()

    case rest do
      [] -> grouped
      [frac] -> grouped <> "," <> frac
    end
  end
end
