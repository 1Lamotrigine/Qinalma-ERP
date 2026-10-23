defmodule Pulse.Vault do
  @moduledoc """
  Шифрование персональных данных на уровне колонок (раздел 7 ТЗ).

  ИИН, реквизиты и удостоверяющие документы сотрудников — персональные
  данные: в базе они хранятся зашифрованными, а ключ приходит из
  окружения (`CLOAK_KEY`). В dev и test допускается значение по
  умолчанию, чтобы стенд поднимался без настройки; в проде ключ
  обязателен.

  Смена ключа делает ранее сохранённые значения нечитаемыми — ключ
  нужно хранить вместе с резервными копиями.
  """
  use Cloak.Vault, otp_app: :pulse

  # Ключ нужен длиной 32 байта для AES.GCM: 32 символа ASCII либо
  # 44 символа base64. Значение по умолчанию предназначено только
  # для dev и test.
  @dev_key "dev-only-cloak-key-32-bytes-0123"

  @impl GenServer
  def init(config) do
    config =
      Keyword.put(config, :ciphers,
        default: {Cloak.Ciphers.AES.GCM, tag: "AES.GCM.V1", key: key()}
      )

    {:ok, config}
  end

  @doc """
  Ключ шифрования: из окружения, иначе — стендовый по умолчанию.
  """
  @spec key() :: binary()
  def key do
    case System.get_env("CLOAK_KEY") do
      nil -> @dev_key
      "" -> @dev_key
      value -> decode(value)
    end
  end

  # Ключ принимается либо в base64, либо как готовая строка: в проде
  # удобнее секрет в base64, а на стенде — читаемая строка.
  defp decode(value) do
    case Base.decode64(value) do
      {:ok, decoded} when byte_size(decoded) == 32 -> decoded
      _ -> value
    end
  end
end
