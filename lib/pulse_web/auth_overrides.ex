defmodule PulseWeb.AuthOverrides do
  @moduledoc """
  Оформление страниц аутентификации AshAuthentication.

  Баннер по умолчанию показывает внешний логотип Ash; заменяем его
  названием приложения, чтобы страница входа не зависела от внешней сети.
  Остальные стили берутся из `AshAuthentication.Phoenix.Overrides.Default`.
  """

  use AshAuthentication.Phoenix.Overrides

  alias AshAuthentication.Phoenix.Components

  override Components.Banner do
    set :image_url, nil
    set :dark_image_url, nil
    set :href_url, nil
    set :text, "Qinalma ERP"
    set :text_class, "text-2xl font-bold tracking-tight text-gray-900 dark:text-white"
  end
end
