defmodule Pulse.Cldr do
  @moduledoc """
  Бэкенд локализации: русский язык по умолчанию, форматы чисел, дат и валют.

  Числа отображаются как «1 757 790», даты — ДД.ММ.ГГГГ. Казахский язык
  добавляется позже отдельной локалью.
  """
  use Cldr,
    locales: ["ru", "en"],
    default_locale: "ru",
    providers: [Cldr.Number, Cldr.Calendar, Cldr.DateTime, Cldr.Number.Formatter.Currency]
end
