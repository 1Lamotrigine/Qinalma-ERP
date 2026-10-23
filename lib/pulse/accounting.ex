defmodule Pulse.Accounting do
  @moduledoc """
  Домен бухгалтерского учёта: план счетов, субконто, типовые операции
  и журнал проводок.

  Документы живут в доменах по разделам (`Pulse.Purchasing`,
  `Pulse.Sales`), а их жизненный цикл, блокировки периода и запись
  движений — в `Pulse.Accounting.Posting`. Проводки пишутся только
  через `Pulse.Accounting.Entries`.
  """
  use Ash.Domain, otp_app: :pulse, extensions: [AshPaperTrail.Domain]

  resources do
    resource Pulse.Accounting.Account do
      define(:list_accounts, action: :read)
    end

    resource Pulse.Accounting.SubaccountType do
      define(:list_subaccount_types, action: :read)
    end

    resource Pulse.Accounting.EntryTemplate do
      define(:list_entry_templates, action: :read)
    end

    resource Pulse.Accounting.JournalEntry do
      define(:list_journal_entries, action: :read)
    end

    paper_trail do
      include_versions?(true)
    end
  end
end
