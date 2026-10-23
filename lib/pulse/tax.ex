defmodule Pulse.Tax do
  @moduledoc """
  Домен налогов: законодательные параметры, НДС и счета-фактуры.

  Всё, что зависит от закона, хранится данными (`Pulse.Tax.StatutoryRate`),
  а не в коде: ставки и пороги меняются, и правка не должна требовать
  релиза.

  **Важно.** Налоговое законодательство Казахстана менялось с 2026 года,
  поэтому значения по умолчанию — ориентир, а не истина в последней
  инстанции. Их нужно сверять с действующей редакцией Налогового кодекса
  и перепроверять с бухгалтером.
  """
  use Ash.Domain, otp_app: :pulse, extensions: [AshPaperTrail.Domain]

  resources do
    resource Pulse.Tax.StatutoryRate do
      define(:list_statutory_rates, action: :read)
    end

    resource Pulse.Tax.Invoice do
      define(:list_invoices, action: :read)
    end

    paper_trail do
      include_versions?(true)
    end
  end
end
