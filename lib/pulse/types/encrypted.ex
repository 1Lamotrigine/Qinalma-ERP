defmodule Pulse.Types.Encrypted do
  @moduledoc """
  Тип Ash для шифруемой колонки персональных данных (раздел 7 ТЗ).

  Значение шифруется при записи и расшифровывается при чтении
  (`Pulse.Vault`). В базе лежит бинарник — зашифрованный текст; в коде
  и в формах значения видны открытым текстом.

  Так шифруются ИИН, удостоверяющие документы и банковские реквизиты
  сотрудников: даже полный дамп базы не раскрывает персональные данные.
  """
  use Ash.Type

  alias Pulse.Vault

  @impl true
  def storage_type(_constraints), do: :binary

  @impl true
  def cast_input(nil, _constraints), do: {:ok, nil}

  def cast_input(value, _constraints) when is_binary(value) do
    {:ok, encrypt(value)}
  end

  def cast_input(value, _constraints) do
    {:ok, encrypt(to_string(value))}
  end

  @impl true
  def cast_stored(nil, _constraints), do: {:ok, nil}

  def cast_stored(value, _constraints) when is_binary(value) do
    {:ok, decrypt(value)}
  end

  def cast_stored(value, _constraints), do: {:ok, decrypt(to_string(value))}

  @impl true
  def dump_to_native(nil, _constraints), do: {:ok, nil}
  def dump_to_native(value, _constraints), do: {:ok, value}

  # Значение уже зашифровано на входе (`cast_input`): повторное
  # шифрование при записи не нужно.
  @impl true
  def apply_constraints(value, _constraints), do: {:ok, value}

  @doc """
  Шифрует значение открытым текстом.
  """
  @spec encrypt(String.t()) :: binary()
  def encrypt(value) do
    {:ok, ciphertext} = Vault.encrypt(value)
    ciphertext
  end

  @doc """
  Расшифровывает значение из базы.
  """
  @spec decrypt(binary() | nil) :: String.t() | nil
  def decrypt(nil), do: nil

  def decrypt(value) do
    case Vault.decrypt(value) do
      {:ok, plaintext} -> plaintext
      # Старое значение неизвестного формата: не роняем чтение.
      _ -> nil
    end
  end
end
