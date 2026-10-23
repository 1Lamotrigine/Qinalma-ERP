defmodule Pulse.HR do
  @moduledoc """
  Домен кадрового учёта: физлица, сотрудники, должности и кадровые
  документы (раздел 5.5 ТЗ).

  Все ресурсы мультитенантны по `organization_id` и аудируются
  AshPaperTrail. Персональные данные (ИИН, документ, реквизиты)
  шифруются в колонках.
  """
  use Ash.Domain, otp_app: :pulse, extensions: [AshPaperTrail.Domain]

  resources do
    resource Pulse.HR.Person do
      define(:list_people, action: :read)
    end

    resource Pulse.HR.Position do
      define(:list_positions, action: :read)
    end

    resource Pulse.HR.Employee do
      define(:list_employees, action: :read)
    end

    resource Pulse.HR.CadreDocument do
      define(:list_cadre_documents, action: :read)
    end

    paper_trail do
      include_versions?(true)
    end
  end
end
