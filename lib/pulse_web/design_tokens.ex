defmodule PulseWeb.DesignTokens do
  @moduledoc """
  Токены оформления из прототипа (index.html).

  Значения перенесены как есть, чтобы плотность таблиц, отступы и цвета
  совпадали с эталоном. Используются как классы Tailwind через
  `PulseWeb.CoreComponents` и напрямую в разметке.
  """

  # Цвета (CSS-переменные объявлены в assets/css/app.css)
  def colors do
    %{
      bg: "var(--bg)",
      card: "var(--card)",
      ink: "var(--ink)",
      muted: "var(--mut)",
      line: "var(--line)",
      accent: "var(--acc)",
      accent_soft: "var(--accs)",
      warn: "var(--amb)",
      warn_soft: "var(--ambs)",
      danger: "var(--bad)"
    }
  end

  @doc """
  Оттенок раздела для иконки: фон и цвет текста (как в прототипе).
  """
  def section_icon_style(hue) do
    "background: hsl(#{hue} 55% 91%); color: hsl(#{hue} 55% 28%)"
  end
end
