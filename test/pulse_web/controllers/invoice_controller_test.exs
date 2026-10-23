defmodule PulseWeb.InvoiceControllerTest do
  @moduledoc """
  Выгрузка счёта-фактуры в XML (этап 7).

  Критерий этапа: счёт-фактура выгружается в XML из интерфейса.
  """
  use PulseWeb.ConnCase, async: true

  import Pulse.Factory

  alias Pulse.Core

  setup do
    seed_default_permissions!()

    organization = create_organization(%{name: "XML-Орг", bin: "190140012345"})
    user = create_user()
    create_membership(user, organization, "admin")

    actor =
      Core.Actor.build(
        user,
        [%{organization_id: organization.id, role: "admin"}],
        organization.id
      )

    counterparty = create_counterparty(actor, %{name: "ТОО «Покупатель»", bin: "120140012345"})

    invoice =
      create_invoice(actor, %{
        direction: :issued,
        number: "СФ-XML-1",
        counterparty_id: counterparty.id
      })

    _ =
      Pulse.Accounts.save_workspace(Pulse.Accounts.load_or_create_workspace(user), user, %{
        active_organization_id: organization.id
      })

    %{conn: log_in_user(build_conn(), user), invoice: invoice}
  end

  test "отдаёт XML счёта-фактуры", %{conn: conn, invoice: invoice} do
    conn = get(conn, ~p"/invoices/#{invoice.id}/xml")

    assert response(conn, 200) =~ ~s(<?xml version="1.0" encoding="UTF-8"?>)
    assert response(conn, 200) =~ "СФ-XML-1"
    assert get_resp_header(conn, "content-type") |> hd() =~ "xml"
    assert [disposition] = get_resp_header(conn, "content-disposition")
    assert disposition =~ "attachment"
  end

  test "неизвестный счёт-фактура — 404", %{conn: conn} do
    conn = get(conn, ~p"/invoices/#{Ecto.UUID.generate()}/xml")
    assert response(conn, 404) =~ "не найдена"
  end
end
