defmodule PulseWeb.InvoiceController do
  @moduledoc """
  Выгрузка счёта-фактуры в XML (этап 7).

  Отдаёт файл, подготовленный `Pulse.Tax.Esf`: данные для ИС ЭСФ,
  собранные по счёту-фактуре и документу-основанию. Требуется вход и
  активная организация.
  """
  use PulseWeb, :controller

  alias Pulse.Tax.Esf
  alias Pulse.Tax.Invoices

  def xml(conn, %{"id" => invoice_id}) do
    with organization_id when is_binary(organization_id) <- organization_id(conn),
         {:ok, {invoice, organization, counterparty}} <-
           Invoices.load(invoice_id, organization_id) do
      {seller, buyer} = Invoices.parties(invoice, organization, counterparty)
      body = Esf.to_xml(invoice, seller, buyer)

      conn
      |> put_resp_content_type("application/xml")
      |> put_resp_header(
        "content-disposition",
        ~s(attachment; filename="#{Esf.filename(invoice)}")
      )
      |> send_resp(200, body)
    else
      _ ->
        conn |> put_status(:not_found) |> text("Счёт-фактура не найдена")
    end
  end

  # Активная организация пользователя — как в рабочей области.
  defp organization_id(conn) do
    case conn.assigns[:current_user] do
      nil ->
        nil

      user ->
        case Pulse.Accounts.load_or_create_workspace(user) do
          %{active_organization_id: organization_id} -> organization_id
          _ -> nil
        end
    end
  end
end
