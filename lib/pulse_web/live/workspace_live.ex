defmodule PulseWeb.WorkspaceLive do
  @moduledoc """
  Рабочая область — единственный LiveView, внутри которого живут вкладки.

  Состояние:
    * `:tabs` — открытые вкладки (список карт), активная задаётся `:active_id`
    * `:hub` — открытый хаб раздела (или `nil`, если показана вкладка)
    * `:favorites` — MapSet идентификаторов избранного
    * `:query` — строка глобального поиска
    * `:actor` — пользователь с активной организацией и ролью (`Pulse.Core.Actor`)
    * `:catalog_rows` / `:catalog_form` — данные и форма открытого справочника
    * `:document_form` — открытый документ с табличной частью

  Вкладки синхронизируются с URL через `push_patch` и сохраняются в
  `user_workspaces`, чтобы восстанавливаться после входа.
  """
  use PulseWeb, :live_view

  alias Pulse.Core
  alias Pulse.Core.Permissions
  alias PulseWeb.Catalogs
  alias PulseWeb.Components.{Combobox, DocumentComponent, HubComponent, JournalComponent}

  alias PulseWeb.Components.{
    InvoiceComponent,
    PayrollComponent,
    ReportComponent,
    Tabs,
    Toast,
    ToolComponent
  }

  alias PulseWeb.{Documents, Menu, Tax}
  alias Pulse.Tax.Esf
  alias Pulse.Tax.Invoices
  require Ash.Query

  @home_tab %{id: "home", title: "Начальная страница", home: true}

  # Демонстрационные контрагенты для журналов, которые ещё не подключены
  # к реальным ресурсам (документы этапа 4+).
  @counterparties [
    "ТОО «Алатау Ритейл»",
    "ИП «Светлова О.И.»",
    "ТОО «ТехноПром Казахстан»",
    "ТОО «КазЭлектро»",
    "ТОО «Степь Логистик»",
    "ИП «Омаров Б.Т.»"
  ]

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    workspace = Pulse.Accounts.load_or_create_workspace(user)

    tabs = restore_tabs(workspace.tabs)
    favorites = MapSet.new(workspace.favorites)

    memberships = load_memberships(user)
    actor = Pulse.Core.Actor.build(user, memberships, workspace.active_organization_id)

    {:ok,
     socket
     |> assign(:page_title, "Qinalma ERP")
     |> assign(:sections, Menu.sections())
     |> assign(:collapsed, false)
     |> assign(:workspace, workspace)
     |> assign(:tabs, tabs)
     |> assign(:active_id, workspace.active_tab || "home")
     |> assign(:hub, nil)
     |> assign(:favorites, favorites)
     |> assign(:favorites_view, favorites)
     |> assign(:query, "")
     |> assign(:results, [])
     |> assign(:hub_filter, "")
     |> assign(:journal_filter, "")
     |> assign(:toast, nil)
     |> assign(:report_result, nil)
     |> assign(:memberships, memberships)
     |> assign(:actor, actor)
     |> assign(:organizations, load_organizations(actor))
     |> assign(:catalog_spec, nil)
     |> assign(:catalog_rows, [])
     |> assign(:catalog_form, nil)
     |> assign(:catalog_ref_options, %{})
     |> assign(:admin_view, nil)
     |> assign(:period_state, nil)
     |> assign(:period_badge, period_badge(actor))
     |> assign(:admin_matrix, [])
     |> assign(:admin_role, nil)
     |> assign(:admin_users, [])
     |> assign(:admin_memberships, [])
     |> assign(:document_spec, nil)
     |> assign(:document_record, nil)
     |> assign(:document_rows, [])
     |> assign(:tax_spec, nil)
     |> assign(:tax_rows, [])
     |> assign(:invoice_view, nil)
     |> assign(:report_spec, nil)
     |> assign(:report_params, %{})
     |> assign(:report_counterparties, [])
     |> assign(:report_employees, [])
     |> assign(:dashboard, dashboard(actor))
     |> assign(:seq, System.unique_integer([:positive]))}
  end

  @impl true
  def handle_params(params, _url, socket) do
    socket =
      case params do
        %{"section" => section_id} ->
          socket
          |> assign(:hub, section_id)
          |> assign(:catalog_form, nil)
          |> assign(:admin_view, nil)
          |> assign(:period_state, nil)

        %{"tab" => tab_id} ->
          socket
          |> assign(:hub, nil)
          |> assign_tab_active(tab_id)
          |> assign(:catalog_form, nil)
          |> load_admin_view(tab_id)
          |> load_period_view(tab_id)

        _ ->
          socket
          |> assign(:hub, nil)
          |> assign(:catalog_form, nil)
          |> assign(:admin_view, nil)
          |> assign(:period_state, nil)
      end

    {:noreply, socket |> load_catalog_rows() |> load_document_rows() |> load_report_spec()}
  end

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> assign(:active_tab, active_tab(assigns))
      |> assign(:journal_columns, journal_columns(assigns))

    ~H"""
    <div class={["ws", @collapsed && "col"]} id="workspace" phx-hook="WorkspaceShortcuts">
      <aside>
        <div class="brand">
          <b>1С</b>
          <span>
            ИП МАРШ <small>Бухгалтерия для Казахстана</small>
          </span>
        </div>

        <nav id="ws-nav">
          <button
            :for={section <- @sections}
            class={["ni", @hub == to_string(section.id) && "on"]}
            phx-click="open-hub"
            phx-value-section={section.id}
          >
            <span class="ic" style={icon_style(section.hue)}>{section.short}</span>
            <span class="lb">{section.title}</span>
          </button>
        </nav>

        <div class="sbf">База: Основная ТМЗ <i>● онлайн</i></div>
      </aside>

      <div class="ws-main">
        <header>
          <button class="ib" phx-click="toggle-sidebar" title="Свернуть меню">☰</button>

          <div class="sw">
            <input
              id="global-search"
              placeholder="Поиск по разделам и документам (Ctrl+K)"
              autocomplete="off"
              value={@query}
              phx-keyup="search"
              phx-debounce="120"
            />
            <div :if={@query != ""} class="res" id="search-results">
              <button
                :for={{section, group, item} <- @results}
                class="rr"
                phx-click="open-search-result"
                phx-value-section={section.id}
                phx-value-group={group}
                phx-value-title={item.title}
              >
                {item.title}
                <small>{section.title} › {group}</small>
              </button>
              <div :if={@results == []} class="empty">Ничего не найдено</div>
            </div>
          </div>

          <div class="sp"></div>

          <select
            :if={@organizations != []}
            class="f"
            id="org-switch"
            name="org"
            phx-change="switch-organization"
            title="Активная организация"
          >
            <option
              :for={org <- @organizations}
              value={org.id}
              selected={org.id == @actor.organization_id}
            >
              {org.name}
            </option>
          </select>

          <span
            :if={@period_badge}
            class={["pill", @period_badge.closed && "p"]}
            id="period-status"
            title={@period_badge.title}
          >
            {@period_badge.label}
          </span>

          <span class="usr" id="current-user" title={role_title(@actor.role)}>
            {format_today()}
            <span class="av">{initial(@current_user.email)}</span>
            {@current_user.email}
          </span>
        </header>

        <Tabs.tabs tabs={@tabs} active_id={@active_id} hub_active={@hub != nil} />
        <div class="ws-view" id="ws-view">
          <%= cond do %>
            <% @period_state != nil -> %>
              <.period_screen state={@period_state} actor={@actor} />
            <% @admin_view != nil -> %>
              <.admin_screen
                view={@admin_view}
                actor={@actor}
                organizations={@organizations}
                memberships={@admin_memberships}
                matrix={@admin_matrix}
                role={@admin_role}
                users={@admin_users}
              />
            <% @catalog_form != nil -> %>
              <.catalog_editor
                spec={@catalog_spec}
                form={@catalog_form}
                ref_options={@catalog_ref_options}
              />
            <% @hub != nil -> %>
              <HubComponent.hub
                section={hub_section(@hub)}
                favorites={@favorites}
                filter={@hub_filter}
              />
            <% Map.get(@active_tab, :home) -> %>
              <.home_view
                sections={@sections}
                favorites={@favorites_view}
                current_user={@current_user}
                organizations={@organizations}
                actor={@actor}
                dashboard={@dashboard}
              />
            <% @invoice_view != nil -> %>
              <InvoiceComponent.invoice
                invoice={@invoice_view.invoice}
                data={@invoice_view.data}
                xml={@invoice_view.xml}
              />
            <% @document_record != nil and match?(%Pulse.Payroll.Accrual{}, @document_record) -> %>
              <PayrollComponent.accrual document={@document_record} />
            <% @document_record != nil -> %>
              <DocumentComponent.document
                spec={@document_spec}
                document={@document_record}
                movements={document_movements(@document_record)}
              />
            <% @active_tab.kind == :journal or @active_tab.kind == :catalog -> %>
              <JournalComponent.journal
                section={section_for(@active_tab)}
                group={@active_tab.group}
                title={@active_tab.title}
                kind={@active_tab.kind}
                columns={@journal_columns}
                rows={journal_tab_rows(assigns)}
                filter={@journal_filter}
              />
            <% @active_tab.kind == :report -> %>
              <ReportComponent.report
                title={@active_tab.title}
                section={section_for(@active_tab)}
                result={@report_result}
                params={@report_params}
                account?={@report_spec != nil and Map.get(@report_spec, :account?, false)}
                counterparty?={@report_spec != nil and Map.get(@report_spec, :counterparty?, false)}
                counterparties={@report_counterparties}
                employee?={@report_spec != nil and Map.get(@report_spec, :employee?, false)}
                employees={@report_employees}
              />
            <% true -> %>
              <ToolComponent.tool
                title={@active_tab.title}
                section={section_for(@active_tab)}
                group={@active_tab.group}
              />
          <% end %>
        </div>
      </div>
    </div>

    <Toast.toast toast={@toast} />
    """
  end

  # ---------------------------------------------------------------------------
  # Начальная страница
  # ---------------------------------------------------------------------------

  attr :sections, :list, required: true
  attr :favorites, :any, required: true
  attr :current_user, :map, required: true
  attr :organizations, :list, required: true
  attr :actor, :map, required: true
  attr :dashboard, :map, required: true

  defp home_view(assigns) do
    assigns = assign(assigns, :favorite_items, favorite_items(assigns.favorites))

    ~H"""
    <div class="tool">
      <h1 style="margin: 0">Сегодня: {format_today()}</h1>
      <div class="sp"></div>
      <select
        :if={@organizations != []}
        class="f"
        id="home-org-switch"
        name="org"
        phx-change="switch-organization"
        title="Активная организация"
      >
        <option
          :for={org <- @organizations}
          value={org.id}
          selected={org.id == @actor.organization_id}
        >
          {org.name}
        </option>
      </select>
      <button
        class="btn p"
        phx-click="quick-create"
        phx-value-title="Реализации ТМЗ и услуг"
      >
        + Реализация
      </button>
      <button
        class="btn"
        phx-click="quick-create"
        phx-value-title="Поступления ТМЗ и услуг"
      >
        + Поступление
      </button>
    </div>

    <div class="home">
      <div class="gr">
        <div class="cd">
          <h2>Остатки денежных средств</h2>
          <div class="row">
            <span>Касса</span>
            <b class="n">{money(@dashboard.cash.cash)}</b>
          </div>
          <div class="row">
            <span>Банк</span>
            <b class={["n", negative?(@dashboard.cash.bank) && "neg"]}>
              {money(@dashboard.cash.bank)}
            </b>
          </div>
          <div class={["row big", negative?(@dashboard.cash.total) && "neg"]}>
            <span></span>
            <span>{money(@dashboard.cash.total)} KZT</span>
          </div>
        </div>

        <div class="cd">
          <h2>Покупатели</h2>
          <div class="row">
            <span>Задолженность</span>
            <b>{money(@dashboard.customers.total)}</b>
          </div>
          <div class="row">
            <span>Просрочено</span>
            <b class="neg">{money(@dashboard.customers.overdue)}</b>
          </div>
          <div class="row">
            <span>Авансы полученные</span>
            <b>{money(@dashboard.customers.advance)}</b>
          </div>
        </div>

        <div class="cd">
          <h2>Продажи</h2>
          <div class="row">
            <span>с начала месяца</span>
            <b>{money(@dashboard.sales.month)}</b>
          </div>
          <div class="row">
            <span>с начала года</span>
            <b>{money(@dashboard.sales.year)}</b>
          </div>
          <div class="row">
            <span>прошлый месяц</span>
            <b>{money(@dashboard.sales.previous_month)}</b>
          </div>
        </div>

        <div class="cd">
          <h2>Поставщики</h2>
          <div class="row">
            <span>Задолженность</span>
            <b>{money(@dashboard.suppliers.total)}</b>
          </div>
          <div class="row">
            <span>Просрочено</span>
            <b class="neg">{money(@dashboard.suppliers.overdue)}</b>
          </div>
          <div class="row">
            <span>Авансы выданные</span>
            <b>{money(@dashboard.suppliers.advance)}</b>
          </div>
        </div>

        <div class="cd">
          <h2>Избранное</h2>
          <button
            :for={{section_id, group, title} <- @favorite_items}
            class="lk"
            phx-click="open-search-result"
            phx-value-section={section_id}
            phx-value-group={group}
            phx-value-title={title}
          >
            {title}
          </button>
          <p :if={@favorite_items == []} class="sub">
            Нажмите ★ у пункта меню, чтобы закрепить его здесь.
          </p>
        </div>
      </div>

      <div class="cd">
        <h2>Текущие дела</h2>
        <p><b>Администрирование</b></p>
        <p class="sub" style="margin-top: 14px">Прочие дела — нет</p>
      </div>
    </div>
    """
  end

  defp money(value), do: PulseWeb.Components.MoneyInput.format_money(value)

  defp negative?(value), do: Decimal.compare(value, 0) == :lt

  # ---------------------------------------------------------------------------
  # Форма элемента справочника
  # ---------------------------------------------------------------------------

  attr :spec, :map, required: true
  attr :form, :any, required: true
  attr :ref_options, :map, default: %{}

  defp catalog_editor(assigns) do
    ~H"""
    <h1>{@spec.title}</h1>
    <p class="sub">Справочник · элемент</p>

    <.form
      for={@form}
      id="catalog-form"
      phx-submit="catalog-save"
      phx-change="catalog-validate"
    >
      <div class="tool">
        <button class="btn p" type="submit">Сохранить</button>
        <button class="btn" type="button" phx-click="catalog-cancel">Отмена</button>
      </div>

      <div class="fm" style="grid-template-columns: repeat(auto-fit, minmax(260px, 1fr))">
        <%= for field <- @spec.fields do %>
          <div :if={field.type == :ref}>
            <label for={"catalog-#{field.name}"}>{field.label}</label>
            <Combobox.combobox
              id={"catalog-#{field.name}"}
              name={"#{@form.name}[#{field.name}]"}
              options={Map.get(@ref_options, field.resource, [])}
              value={@form[field.name].value}
            />
          </div>

          <.input
            :if={field.type != :ref}
            field={@form[field.name]}
            type={input_type(field)}
            label={field.label}
            options={Map.get(field, :options, [])}
            step={step_for(field)}
          />
        <% end %>
      </div>
    </.form>
    """
  end

  defp input_type(%{type: :text}), do: "text"
  defp input_type(%{type: :textarea}), do: "textarea"
  defp input_type(%{type: :select}), do: "select"
  defp input_type(%{type: :number}), do: "number"
  defp input_type(%{type: :date}), do: "date"

  defp step_for(%{type: :number}), do: "any"
  defp step_for(_field), do: nil

  # ---------------------------------------------------------------------------
  # Администрирование: пользователи, роли, матрица прав
  # ---------------------------------------------------------------------------

  # ---------------------------------------------------------------------------
  # Экран управления периодами
  # ---------------------------------------------------------------------------

  attr :state, :map, required: true
  attr :actor, :map, required: true

  defp period_screen(assigns) do
    ~H"""
    <h1>Закрытие месяца</h1>
    <p class="sub">Операции · регламентные операции</p>

    <div class="tool">
      <span class="pill" class={["pill", @state.closed && "p"]}>
        {if @state.closed, do: "Месяц закрыт", else: "Месяц открыт"}
      </span>
      <div class="sp"></div>
      <span class="sub">Текущий месяц: {month_label(@state.current)}</span>
    </div>

    <div class="cd">
      <h2>Закрытие месяца</h2>
      <p class="sub">
        Закрытие пересчитывает себестоимость месяца и запрещает правки.
        Открыть месяц обратно может только главный бухгалтер.
      </p>

      <div class="tool" style="margin-top: 10px">
        <button
          :if={not @state.closed}
          class="btn p"
          id="close-month"
          phx-click="period-close"
        >
          Закрыть {month_label(@state.current)}
        </button>
        <button
          :if={@state.closed}
          class="btn"
          id="reopen-month"
          phx-click="period-reopen"
        >
          Открыть {month_label(@state.current)}
        </button>
      </div>
    </div>

    <div class="cd" style="margin-top: 16px">
      <h2>Дата запрета изменения данных</h2>
      <p class="sub">
        Документы с датой раньше этой границы менять нельзя.
        Главный бухгалтер и администратор обходят запрет.
      </p>

      <div class="tool" style="margin-top: 10px">
        <input
          class="f"
          id="prohibition-date"
          type="date"
          value={@state.prohibition_date && Date.to_string(@state.prohibition_date)}
          phx-change="period-set-prohibition"
        />
        <button class="btn" phx-click="period-clear-prohibition">Снять запрет</button>
      </div>
    </div>

    <div class="cd" style="margin-top: 16px">
      <h2>Закрытые периоды</h2>
      <table id="closed-periods">
        <thead>
          <tr>
            <th>Месяц</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={period <- @state.closed_periods}>
            <td>{month_label(period)}</td>
          </tr>
          <tr :if={@state.closed_periods == []}>
            <td class="empty">Закрытых периодов нет</td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  defp month_label(date), do: Pulse.Accounting.Periods.month_label(date)

  attr :view, :atom, required: true
  attr :actor, :map, required: true
  attr :organizations, :list, required: true
  attr :memberships, :list, required: true
  attr :matrix, :list, required: true
  attr :role, :string, default: nil
  attr :users, :list, required: true

  defp admin_screen(assigns) do
    ~H"""
    <h1>Настройки пользователей и прав</h1>
    <p class="sub">Администрирование · роли и матрица прав</p>

    <div class="tool">
      <button
        class={["btn", @view == :users && "p"]}
        phx-click="admin-view"
        phx-value-view="users"
      >
        Пользователи
      </button>
      <button
        class={["btn", @view == :matrix && "p"]}
        phx-click="admin-view"
        phx-value-view="matrix"
      >
        Матрица прав
      </button>
    </div>

    <%= if @view == :users do %>
      <div class="cd">
        <h2>Пользователи и роли</h2>
        <table id="admin-users">
          <thead>
            <tr>
              <th>Пользователь</th>
              <th>Организация</th>
              <th>Роль</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={membership <- @memberships} id={"membership-#{membership.id}"}>
              <td>{user_email(@users, membership.user_id)}</td>
              <td>{organization_name(@organizations, membership.organization_id)}</td>
              <td>
                <select
                  class="f"
                  name="role"
                  phx-change="admin-change-role"
                  phx-value-id={membership.id}
                >
                  <option
                    :for={{key, title} <- role_options()}
                    value={key}
                    selected={key == membership.role}
                  >
                    {title}
                  </option>
                </select>
              </td>
            </tr>
            <tr :if={@memberships == []}>
              <td colspan="3" class="empty">Нет пользователей в организациях</td>
            </tr>
          </tbody>
        </table>
      </div>
    <% end %>

    <%= if @view == :matrix do %>
      <div class="tool">
        <select class="f" id="admin-role" name="role" phx-change="admin-pick-role">
          <option
            :for={{key, title} <- role_options()}
            value={key}
            selected={key == @role}
          >
            {title}
          </option>
        </select>
        <div class="sp"></div>
        <span class="sub">{matrix_hint(@role)}</span>
      </div>

      <div class="cd">
        <table id="admin-matrix">
          <thead>
            <tr>
              <th>Ресурс</th>
              <th :for={action <- action_options()}>{action_label(action)}</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={resource <- resource_options()}>
              <td>{resource_label(resource)}</td>
              <td :for={action <- action_options()}>
                <input
                  type="checkbox"
                  id={"perm-#{@role}-#{resource}-#{action}"}
                  checked={matrix_allowed?(@matrix, @role, resource, action)}
                  phx-click="admin-toggle-permission"
                  phx-value-role={@role}
                  phx-value-resource={resource}
                  phx-value-action={action}
                />
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    <% end %>
    """
  end

  defp role_options, do: Core.Roles.list()

  defp action_options, do: Core.Roles.actions()

  defp resource_options, do: Core.Roles.resources()

  defp action_label("read"), do: "Чтение"
  defp action_label("create"), do: "Создание"
  defp action_label("update"), do: "Изменение"
  defp action_label("destroy"), do: "Удаление"
  defp action_label(action), do: action

  defp resource_label(resource) do
    resource
    |> String.split(".")
    |> List.last()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp matrix_hint(nil), do: "Выберите роль"
  defp matrix_hint(role), do: "Роль: #{Core.Roles.title(role)} · отметьте разрешённые действия"

  defp matrix_allowed?(matrix, role, resource, action) do
    {role, resource, action} in matrix
  end

  defp user_email(users, user_id) do
    Enum.find_value(users, user_id, fn user ->
      if user.id == user_id, do: to_string(user.email)
    end)
  end

  defp organization_name(organizations, organization_id) do
    Enum.find_value(organizations, organization_id, fn organization ->
      if organization.id == organization_id, do: organization.name
    end)
  end

  # ---------------------------------------------------------------------------
  # Данные справочников
  # ---------------------------------------------------------------------------

  defp load_memberships(user) do
    Pulse.Core.OrganizationMembership
    |> Ash.Query.filter(user_id == ^user.id)
    |> Ash.read(actor: user)
    |> case do
      {:ok, memberships} -> memberships
      _ -> []
    end
  end

  defp load_organizations(actor) do
    case Ash.read(Core.Organization, actor: actor) do
      {:ok, organizations} -> organizations
      _ -> []
    end
  end

  defp load_catalog_rows(socket) do
    case active_catalog_spec(socket.assigns) do
      nil ->
        socket |> assign(:catalog_spec, nil) |> assign(:catalog_rows, [])

      spec ->
        case Catalogs.list(spec, socket.assigns.actor) do
          {:ok, rows} ->
            socket |> assign(:catalog_spec, spec) |> assign(:catalog_rows, rows)

          {:error, message} ->
            socket
            |> assign(:catalog_spec, spec)
            |> assign(:catalog_rows, [])
            |> put_toast(message)
        end
    end
  end

  defp active_catalog_spec(assigns) do
    tab = active_tab(assigns)

    if tab && Map.get(tab, :kind) == :catalog do
      Catalogs.spec(tab.title)
    end
  end

  # ---------------------------------------------------------------------------
  # Данные документов
  # ---------------------------------------------------------------------------

  defp load_document_rows(socket) do
    loaded = load_tax_rows(socket)

    case loaded.assigns.tax_spec do
      spec when not is_nil(spec) ->
        loaded |> assign(:document_spec, nil) |> assign(:document_rows, [])

      _ ->
        case active_document_spec(loaded.assigns) do
          nil ->
            loaded |> assign(:document_spec, nil) |> assign(:document_rows, [])

          spec ->
            case Documents.list(spec, loaded.assigns.actor) do
              {:ok, rows} ->
                loaded |> assign(:document_spec, spec) |> assign(:document_rows, rows)

              {:error, message} ->
                loaded
                |> assign(:document_spec, spec)
                |> assign(:document_rows, [])
                |> put_toast(message)
            end
        end
    end
  end

  # Журналы счетов-фактур: отдельный реестр, потому что счёт-фактура
  # формируется по документу, а не вводится руками.
  defp load_tax_rows(socket) do
    case active_tax_spec(socket.assigns) do
      nil ->
        socket |> assign(:tax_spec, nil) |> assign(:tax_rows, [])

      spec ->
        case Tax.list(spec, socket.assigns.actor) do
          {:ok, rows} -> socket |> assign(:tax_spec, spec) |> assign(:tax_rows, rows)
          {:error, _message} -> socket |> assign(:tax_spec, spec) |> assign(:tax_rows, [])
        end
    end
  end

  defp active_tax_spec(assigns) do
    tab = active_tab(assigns)

    if tab && Map.get(tab, :kind) == :journal do
      Tax.spec(tab.title)
    end
  end

  defp active_document_spec(assigns) do
    tab = active_tab(assigns)

    if tab && Map.get(tab, :kind) == :journal do
      Documents.spec(tab.title)
    end
  end

  defp journal_columns(%{document_spec: spec}) when not is_nil(spec), do: spec.columns
  defp journal_columns(%{tax_spec: spec}) when not is_nil(spec), do: spec.columns
  defp journal_columns(%{catalog_spec: spec}) when not is_nil(spec), do: spec.columns
  defp journal_columns(_assigns), do: []

  defp journal_tab_rows(%{document_spec: spec, document_rows: rows}) when not is_nil(spec),
    do: rows

  defp journal_tab_rows(%{tax_spec: spec, tax_rows: rows}) when not is_nil(spec), do: rows

  defp journal_tab_rows(%{catalog_spec: spec, catalog_rows: rows}) when not is_nil(spec),
    do: rows

  defp journal_tab_rows(assigns), do: journal_rows(assigns.active_tab)

  defp document_movements(%{status: :posted} = document), do: Documents.movements(document)

  defp document_movements(_document), do: []

  # ---------------------------------------------------------------------------
  # Отчёты
  # ---------------------------------------------------------------------------

  defp active_report_spec(assigns) do
    tab = active_tab(assigns)

    if tab && Map.get(tab, :kind) == :report do
      PulseWeb.Reports.spec(tab.title)
    end
  end

  defp load_report_spec(socket) do
    socket
    |> assign(:report_spec, active_report_spec(socket.assigns))
    |> assign(:report_counterparties, counterparty_options(socket.assigns.actor))
    |> assign(:report_employees, employee_options(socket.assigns.actor))
  end

  # Список сотрудников для отчётов, где нужен выбор (расчётный листок).
  defp employee_options(actor) do
    if is_nil(actor.organization_id) do
      []
    else
      Pulse.HR.Employee
      |> Ash.Query.load([:person])
      |> Ash.read(tenant: actor.organization_id, authorize?: false)
      |> case do
        {:ok, employees} -> Enum.map(employees, &{&1.id, employee_label(&1)})
        _ -> []
      end
    end
  end

  defp employee_label(%{person: %Ash.NotLoaded{}} = employee), do: employee.id
  defp employee_label(%{person: nil} = employee), do: employee.id
  defp employee_label(%{person: person}), do: Pulse.HR.Person.full_name(person)

  # Список контрагентов для отчётов, где нужен выбор (акт сверки).
  defp counterparty_options(actor) do
    if is_nil(actor.organization_id) do
      []
    else
      Pulse.Catalog.Counterparty
      |> Ash.Query.sort(name: :asc)
      |> Ash.read(actor: actor, tenant: actor.organization_id)
      |> case do
        {:ok, counterparties} -> Enum.map(counterparties, &{&1.id, &1.name})
        _ -> []
      end
    end
  end

  # Параметры отчёта приходят из полей формы; то, что не передано,
  # сохраняется с прошлого формирования.
  defp apply_report_params(socket, params) do
    params =
      params
      |> Map.take(["from", "to", "account", "counterparty"])
      |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
      |> Map.new()

    assign(socket, :report_params, Map.merge(socket.assigns.report_params, params))
  end

  defp active_organization_name(socket) do
    Enum.find_value(socket.assigns.organizations, "организация не выбрана", fn organization ->
      if organization.id == socket.assigns.actor.organization_id, do: organization.name
    end)
  end

  # Показатели начальной страницы: деньги, долги и продажи.
  defp dashboard(actor) do
    if is_nil(actor.organization_id) do
      empty_dashboard()
    else
      Pulse.Reporting.dashboard(actor.organization_id, Date.utc_today())
    end
  end

  defp empty_dashboard do
    zero = Decimal.new(0)

    %{
      date: Date.utc_today(),
      cash: %{cash: zero, bank: zero, total: zero},
      customers: %{total: zero, overdue: zero, advance: zero},
      suppliers: %{total: zero, overdue: zero, advance: zero},
      sales: %{month: zero, year: zero, previous_month: zero}
    }
  end

  defp role_title(nil), do: "Роль не назначена"
  defp role_title(role), do: Core.Roles.title(role)

  # ---------------------------------------------------------------------------
  # События: навигация
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("toggle-sidebar", _params, socket) do
    {:noreply, update(socket, :collapsed, &(!&1))}
  end

  def handle_event("open-hub", %{"section" => section_id}, socket) do
    {:noreply,
     socket
     |> assign(:hub, section_id)
     |> assign(:hub_filter, "")
     |> push_patch(to: ~p"/?section=#{section_id}", replace: true)}
  end

  def handle_event("filter-hub", %{"value" => filter}, socket) do
    {:noreply, assign(socket, :hub_filter, filter)}
  end

  def handle_event("open-item", params, socket) do
    %{"section" => section_id, "group" => group, "title" => title} = params

    {:noreply, socket |> open_item(section_id, group, title) |> assign(:hub, nil)}
  end

  def handle_event("open-search-result", params, socket) do
    %{"section" => section_id, "group" => group, "title" => title} = params

    {:noreply,
     socket
     |> open_item(section_id, group, title)
     |> assign(:hub, nil)
     |> assign(:query, "")
     |> assign(:results, [])}
  end

  def handle_event("switch-tab", %{"id" => id}, socket) do
    {:noreply,
     socket
     |> assign(:active_id, id)
     |> assign(:hub, nil)
     |> persist_workspace()
     |> push_patch(to: ~p"/?tab=#{id}", replace: true)}
  end

  def handle_event("close-tab", %{"id" => id}, socket) do
    tabs = Enum.reject(socket.assigns.tabs, &(&1.id == id))
    tabs = if tabs == [], do: [@home_tab], else: tabs

    was_active = socket.assigns.active_id == id

    active_id =
      if was_active do
        List.last(tabs).id
      else
        socket.assigns.active_id
      end

    socket =
      socket
      |> assign(:tabs, tabs)
      |> assign(:active_id, active_id)
      |> persist_workspace()

    socket =
      if was_active do
        push_patch(socket, to: ~p"/?tab=#{active_id}", replace: true)
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_event("close-active-tab", _params, socket) do
    handle_event("close-tab", %{"id" => socket.assigns.active_id}, socket)
  end

  # ---------------------------------------------------------------------------
  # События: поиск и избранное
  # ---------------------------------------------------------------------------

  def handle_event("search", %{"value" => query}, socket) do
    {:noreply,
     socket
     |> assign(:query, query)
     |> assign(:results, Menu.search(query))}
  end

  def handle_event("close-search", _params, socket) do
    {:noreply, socket |> assign(:query, "") |> assign(:results, [])}
  end

  def handle_event("toggle-favorite", %{"section" => section_id, "title" => title}, socket) do
    key = "#{section_id}|#{title}"

    favorites =
      if MapSet.member?(socket.assigns.favorites, key) do
        MapSet.delete(socket.assigns.favorites, key)
      else
        MapSet.put(socket.assigns.favorites, key)
      end

    {:noreply,
     socket
     |> assign(:favorites, favorites)
     |> assign(:favorites_view, favorites)
     |> persist_workspace()}
  end

  # ---------------------------------------------------------------------------
  # События: журнал
  # ---------------------------------------------------------------------------

  def handle_event("filter-journal", %{"value" => filter}, socket) do
    {:noreply, assign(socket, :journal_filter, filter)}
  end

  def handle_event("create-document", %{"title" => title}, socket) do
    cond do
      PulseWeb.Periods.screen?(title) ->
        {:noreply, socket |> open_periods() |> assign(:hub, nil)}

      admin_view_for(title) ->
        {:noreply, socket |> open_admin(admin_view_for(title)) |> assign(:hub, nil)}

      Catalogs.spec(title) ->
        {:noreply, socket |> open_catalog(Catalogs.spec(title), nil) |> assign(:hub, nil)}

      Documents.form_spec(title) ->
        {:noreply, socket |> open_document_form(title) |> assign(:hub, nil)}

      Tax.spec(title) ->
        # Счёт-фактура формируется по проведённому документу, а не вручную.
        {:noreply,
         put_toast(
           socket,
           "Счёт-фактура формируется по проведённому документу реализации или поступления"
         )}

      true ->
        {:noreply, socket |> open_document(title) |> assign(:hub, nil)}
    end
  end

  def handle_event("quick-create", %{"title" => title}, socket) do
    {:noreply, socket |> open_document(title) |> assign(:hub, nil)}
  end

  def handle_event("open-document", params, socket) do
    cond do
      spec = active_document_spec(socket.assigns) ->
        open_document_record(socket, spec, params["id"])

      spec = active_catalog_spec(socket.assigns) ->
        open_catalog_record(socket, spec, params["id"])

      spec = active_tax_spec(socket.assigns) ->
        # Счета-фактуры формируются по документам — открываем печатную форму.
        open_invoice(socket, spec, params["id"])

      true ->
        {:noreply, put_toast(socket, "Форма документа появится на этапе 4")}
    end
  end

  # ---------------------------------------------------------------------------
  # События: форма элемента справочника
  # ---------------------------------------------------------------------------

  def handle_event("catalog-validate", %{"catalog" => params}, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.catalog_form, params)
    {:noreply, assign(socket, :catalog_form, form)}
  end

  def handle_event("catalog-cancel", _params, socket) do
    {:noreply, assign(socket, :catalog_form, nil)}
  end

  def handle_event("catalog-save", params, socket) do
    form = socket.assigns.catalog_form

    case AshPhoenix.Form.submit(form, params: Map.get(params, "catalog", %{})) do
      {:ok, _record} ->
        socket =
          socket
          |> assign(:catalog_form, nil)
          |> load_catalog_rows()
          |> load_document_rows()

        {:noreply, put_toast(socket, "Сохранено")}

      {:error, form} ->
        {:noreply, socket |> assign(:catalog_form, form) |> put_toast("Проверьте поля формы")}
    end
  end

  def handle_event("save-document", _params, socket) do
    {:noreply, post_open_document(socket)}
  end

  def handle_event("unpost-document", _params, socket) do
    {:noreply, unpost_open_document(socket)}
  end

  def handle_event("close-document", _params, socket) do
    {:noreply, assign(socket, document_record: nil, invoice_view: nil)}
  end

  # Проведение из журнала: строка журнала несёт идентификатор документа.
  def handle_event("post-document-row", %{"id" => document_id}, socket) do
    case active_document_spec(socket.assigns) do
      nil ->
        {:noreply, socket}

      spec ->
        case Documents.fetch(spec, document_id, socket.assigns.actor) do
          {:ok, document} -> {:noreply, post_document(socket, document, spec)}
          {:error, _error} -> {:noreply, put_toast(socket, "Документ не найден")}
        end
    end
  end

  # ---------------------------------------------------------------------------
  # События: отчёт и уведомления
  # ---------------------------------------------------------------------------

  def handle_event("generate-report", params, socket) do
    socket = apply_report_params(socket, params)

    case active_report_spec(socket.assigns) do
      nil ->
        # Отчёт этапа 5+ : показываем демонстрационный результат.
        {:noreply,
         socket
         |> assign(:report_result, demo_report())
         |> put_toast("Отчет сформирован")}

      spec ->
        case PulseWeb.Reports.build(spec, socket.assigns.report_params, socket.assigns.actor) do
          {:ok, result} ->
            {:noreply,
             socket
             |> assign(:report_result, result)
             |> put_toast("Отчет сформирован")}

          {:error, message} ->
            {:noreply, put_toast(socket, message)}
        end
    end
  end

  def handle_event("report-period", params, socket) do
    {:noreply, apply_report_params(socket, params)}
  end

  def handle_event("toast", %{"message" => message}, socket) do
    {:noreply, put_toast(socket, message)}
  end

  def handle_event("clear-toast", _params, socket) do
    {:noreply, assign(socket, :toast, nil)}
  end

  # ---------------------------------------------------------------------------
  # События: активная организация
  # ---------------------------------------------------------------------------

  def handle_event("switch-organization", params, socket) do
    organization_id = params["value"] || params["org"]

    cond do
      is_nil(organization_id) or organization_id == "" ->
        {:noreply, socket}

      organization_id == socket.assigns.actor.organization_id ->
        {:noreply, socket}

      not Enum.any?(socket.assigns.organizations, &(&1.id == organization_id)) ->
        {:noreply, socket}

      true ->
        actor =
          Pulse.Core.Actor.build(
            socket.assigns.current_user,
            socket.assigns.memberships,
            organization_id
          )

        _ =
          Pulse.Accounts.save_workspace(socket.assigns.workspace, socket.assigns.current_user, %{
            active_organization_id: organization_id
          })

        socket =
          socket
          |> assign(:actor, actor)
          |> assign(:catalog_form, nil)
          |> assign(:dashboard, dashboard(actor))
          |> maybe_refresh_admin()
          |> load_catalog_rows()

        {:noreply, put_toast(socket, "Активная организация: #{active_organization_name(socket)}")}
    end
  end

  # ---------------------------------------------------------------------------
  # События: администрирование
  # ---------------------------------------------------------------------------

  def handle_event("admin-view", %{"view" => view}, socket) do
    {:noreply, open_admin(socket, String.to_existing_atom(view))}
  end

  def handle_event("admin-pick-role", %{"role" => role}, socket) do
    {:noreply, assign(socket, admin_role: role, admin_matrix: Permissions.dump())}
  end

  def handle_event("admin-toggle-permission", params, socket) do
    %{"role" => role, "resource" => resource, "action" => action} = params

    socket =
      case toggle_permission(role, resource, action) do
        :ok -> assign(socket, :admin_matrix, Permissions.dump())
        {:error, message} -> put_toast(socket, message)
      end

    {:noreply, socket}
  end

  def handle_event("admin-change-role", params, socket) do
    membership_id = params["id"]
    role = params["role"]

    membership = Enum.find(socket.assigns.admin_memberships, &(&1.id == membership_id))

    socket =
      case membership && change_membership_role(membership, role, socket.assigns.actor) do
        {:ok, updated} ->
          memberships = replace_membership(socket.assigns.admin_memberships, updated)

          socket
          |> assign(:admin_memberships, memberships)
          |> put_toast("Роль изменена: #{Core.Roles.title(role)}")

        {:error, _error} ->
          put_toast(socket, "Не удалось изменить роль")

        nil ->
          socket
      end

    {:noreply, socket}
  end

  # ---------------------------------------------------------------------------
  # События: периоды
  # ---------------------------------------------------------------------------

  def handle_event("period-close", _params, socket) do
    case close_current_month(socket) do
      {:ok, label} ->
        {:noreply,
         socket
         |> open_periods()
         |> put_toast("Месяц #{label} закрыт")}

      {:error, message} ->
        {:noreply, put_toast(socket, message)}
    end
  end

  def handle_event("period-reopen", _params, socket) do
    state = socket.assigns.period_state
    actor = socket.assigns.actor

    case state && PulseWeb.Periods.reopen_month(state.current, actor.organization_id, actor) do
      :ok ->
        {:noreply,
         socket
         |> open_periods()
         |> put_toast("Месяц открыт заново")}

      {:error, message} ->
        {:noreply, put_toast(socket, message)}

      nil ->
        {:noreply, socket}
    end
  end

  def handle_event("period-set-prohibition", %{"value" => value}, socket) do
    state = socket.assigns.period_state
    actor = socket.assigns.actor

    if is_nil(state) do
      {:noreply, socket}
    else
      {:noreply, set_prohibition(socket, value, actor)}
    end
  end

  def handle_event("period-clear-prohibition", _params, socket) do
    state = socket.assigns.period_state
    actor = socket.assigns.actor

    case state && PulseWeb.Periods.set_prohibition_date(nil, actor.organization_id, actor) do
      :ok ->
        {:noreply, socket |> open_periods() |> put_toast("Дата запрета снята")}

      {:error, message} ->
        {:noreply, put_toast(socket, message)}

      nil ->
        {:noreply, socket}
    end
  end

  defp replace_membership(memberships, updated) do
    Enum.map(memberships, fn membership ->
      if membership.id == updated.id, do: updated, else: membership
    end)
  end

  defp open_document_record(socket, spec, document_id) do
    case Documents.fetch(spec, document_id, socket.assigns.actor) do
      {:ok, document} ->
        {:noreply, assign(socket, document_record: document, document_spec: spec, hub: nil)}

      {:error, :forbidden} ->
        {:noreply, put_toast(socket, "Нет прав на просмотр документа")}

      {:error, _error} ->
        {:noreply, put_toast(socket, "Документ не найден")}
    end
  end

  defp open_catalog_record(socket, spec, record_id) do
    case Catalogs.fetch(spec, record_id, socket.assigns.actor) do
      {:ok, record} ->
        {:noreply, open_catalog(socket, spec, record)}

      {:error, :forbidden} ->
        {:noreply, put_toast(socket, "Нет прав на редактирование")}

      {:error, _error} ->
        {:noreply, put_toast(socket, "Запись не найдена")}
    end
  end

  # Печатная форма счёта-фактуры с выгрузкой XML. Счёт-фактура только
  # читается: она сформирована по документу-основанию.
  defp open_invoice(socket, _spec, invoice_id) do
    organization_id = socket.assigns.actor.organization_id

    case Invoices.load(invoice_id, organization_id) do
      {:ok, {invoice, organization, counterparty}} ->
        {seller, buyer} = Invoices.parties(invoice, organization, counterparty)

        view = %{
          invoice: invoice,
          data: Esf.data(invoice, seller, buyer),
          xml: Esf.to_xml(invoice, seller, buyer)
        }

        {:noreply, assign(socket, invoice_view: view, hub: nil)}

      {:error, _error} ->
        {:noreply, put_toast(socket, "Счёт-фактура не найден")}
    end
  end

  defp post_open_document(%{assigns: %{document_record: nil}} = socket), do: socket

  defp post_open_document(socket) do
    post_document(socket, socket.assigns.document_record, socket.assigns.document_spec)
  end

  defp post_document(socket, document, spec) do
    case Documents.post(document, socket.assigns.actor, spec) do
      {:ok, posted} ->
        socket
        |> assign(:document_record, posted)
        |> load_document_rows()
        |> put_toast("Документ проведён: #{posted.number || "без номера"}")

      {:error, message} ->
        put_toast(socket, message)
    end
  end

  defp unpost_open_document(%{assigns: %{document_record: nil}} = socket), do: socket

  defp unpost_open_document(socket) do
    document = socket.assigns.document_record
    spec = socket.assigns.document_spec

    case Documents.unpost(document, socket.assigns.actor, spec) do
      {:ok, draft} ->
        socket
        |> assign(:document_record, draft)
        |> load_document_rows()
        |> put_toast("Проведение отменено")

      {:error, message} ->
        put_toast(socket, message)
    end
  end

  defp close_current_month(socket) do
    state = socket.assigns.period_state
    actor = socket.assigns.actor

    case state && PulseWeb.Periods.close_month(state.current, actor.organization_id, actor) do
      {:ok, %{period: period}} -> {:ok, Pulse.Accounting.Periods.month_label(period)}
      {:error, message} -> {:error, message}
      nil -> {:error, "выберите активную организацию"}
    end
  end

  defp parse_date(value) when is_binary(value) and value != "" do
    case Date.from_iso8601(value) do
      {:ok, date} -> {:ok, date}
      _ -> {:error, "неверная дата"}
    end
  end

  defp parse_date(_value), do: {:error, "неверная дата"}

  # Установка даты запрета: ошибки показываются уведомлением.
  defp set_prohibition(socket, value, actor) do
    with {:ok, date} <- parse_date(value),
         :ok <- PulseWeb.Periods.set_prohibition_date(date, actor.organization_id, actor) do
      socket
      |> open_periods()
      |> put_toast("Дата запрета: #{Date.to_string(date)}")
    else
      {:error, message} -> put_toast(socket, message)
    end
  end

  # ---------------------------------------------------------------------------
  # Вспомогательное
  # ---------------------------------------------------------------------------

  defp open_item(socket, section_id, group, title) do
    section_atom = String.to_existing_atom(section_id)
    kind = Menu.kind(section_atom, title)
    id = "#{section_id}|#{title}"

    tabs =
      if Enum.any?(socket.assigns.tabs, &(&1.id == id)) do
        socket.assigns.tabs
      else
        socket.assigns.tabs ++
          [%{id: id, title: title, kind: kind, group: group, section: section_atom}]
      end

    socket
    |> assign(:tabs, tabs)
    |> assign(:active_id, id)
    |> assign(:journal_filter, "")
    |> assign(:report_result, nil)
    |> assign(:catalog_form, nil)
    |> assign(:admin_view, nil)
    |> persist_workspace()
    |> push_patch(to: ~p"/?tab=#{id}", replace: true)
  end

  defp open_document(socket, title) do
    section_id = Menu.section_id(title)
    section = section_id && Menu.get(section_id)
    id = "doc-#{title}-#{System.unique_integer([:positive])}"

    tab = %{
      id: id,
      title: "Новый документ: #{title}",
      kind: :document,
      group: "",
      section: section_id,
      lines: [%{good: 0, qty: 1}]
    }

    _ = section

    socket
    |> assign(:tabs, socket.assigns.tabs ++ [tab])
    |> assign(:active_id, id)
    |> persist_workspace()
    |> push_patch(to: ~p"/?tab=#{id}", replace: true)
  end

  # ---------------------------------------------------------------------------
  # Администрирование: загрузка и изменение
  # ---------------------------------------------------------------------------

  defp admin_view_for("Настройки пользователей и прав"), do: :matrix
  defp admin_view_for(_title), do: nil

  # Экран администрирования открывается по вкладке `раздел|заголовок`.
  defp load_admin_view(socket, tab_id) do
    case String.split(tab_id, "|", parts: 2) do
      [_section, title] ->
        case admin_view_for(title) do
          nil -> assign(socket, :admin_view, nil)
          view -> open_admin(socket, view)
        end

      _ ->
        assign(socket, :admin_view, nil)
    end
  end

  # Экран периодов открывается по своим пунктам меню.
  defp load_period_view(socket, tab_id) do
    case String.split(tab_id, "|", parts: 2) do
      [_section, title] ->
        if PulseWeb.Periods.screen?(title) do
          open_periods(socket)
        else
          assign(socket, :period_state, nil)
        end

      _ ->
        assign(socket, :period_state, nil)
    end
  end

  defp open_periods(socket) do
    actor = socket.assigns.actor

    state =
      if is_nil(actor.organization_id) do
        nil
      else
        PulseWeb.Periods.state(actor.organization_id, Date.utc_today())
      end

    socket
    |> assign(:period_state, state)
    |> assign(:catalog_form, nil)
    |> assign(:admin_view, nil)
    |> assign(:hub, nil)
  end

  # Статус периода в шапке: руководителю и бухгалтеру важно видеть,
  # закрыт ли текущий месяц, не открывая экран периодов.
  defp period_badge(actor) do
    if is_nil(actor.organization_id) do
      nil
    else
      today = Date.utc_today()
      closed = Pulse.Accounting.Periods.closed?(today, actor.organization_id)
      label = Pulse.Accounting.Periods.month_label(today)

      %{
        closed: closed,
        label: if(closed, do: "#{label} закрыт", else: "#{label} открыт"),
        title: "Статус учетного периода"
      }
    end
  end

  defp open_admin(socket, view) do
    socket
    |> assign(:admin_view, view)
    |> assign(:admin_role, socket.assigns.admin_role || "admin")
    |> assign(:admin_matrix, Permissions.dump())
    |> assign(:admin_users, load_users())
    |> assign(:admin_memberships, load_admin_memberships(socket.assigns.actor))
    |> assign(:catalog_form, nil)
    |> assign(:hub, nil)
  end

  defp load_users do
    case Ash.read(Pulse.Accounts.User, authorize?: false) do
      {:ok, users} -> users
      _ -> []
    end
  end

  # Участники активной организации — для экрана администрирования.
  defp load_admin_memberships(actor) do
    query =
      Core.OrganizationMembership
      |> Ash.Query.filter(organization_id == ^actor.organization_id)

    case Ash.read(query, actor: actor) do
      {:ok, memberships} -> memberships
      _ -> []
    end
  end

  defp maybe_refresh_admin(%{assigns: %{admin_view: nil}} = socket), do: socket

  defp maybe_refresh_admin(socket) do
    assign(socket, :admin_memberships, load_admin_memberships(socket.assigns.actor))
  end

  defp toggle_permission(role, resource, action) do
    allowed? = {role, resource, action} in Permissions.dump()
    change_permission(role, resource, action, not allowed?)
  end

  defp change_permission(role, resource, action, allowed?) do
    query =
      Core.RolePermission
      |> Ash.Query.filter(role == ^role and resource == ^resource and action == ^action)

    with {:ok, rows} <- Ash.read(query, authorize?: false),
         result <- write_permission(rows, role, resource, action, allowed?) do
      case result do
        {:ok, _row} -> :ok
        {:error, error} -> {:error, "Не удалось изменить право: #{Exception.message(error)}"}
      end
    else
      {:error, error} -> {:error, "Не удалось прочитать матрицу: #{Exception.message(error)}"}
    end
  end

  defp write_permission([row | _], _role, _resource, _action, allowed?) do
    row
    |> Ash.Changeset.for_update(:update, %{allowed?: allowed?})
    |> Ash.update(authorize?: false)
  end

  defp write_permission([], role, resource, action, allowed?) do
    Core.RolePermission
    |> Ash.Changeset.for_create(:create, %{
      role: role,
      resource: resource,
      action: action,
      allowed?: allowed?
    })
    |> Ash.create(authorize?: false)
  end

  defp change_membership_role(membership, role, actor) do
    membership
    |> Ash.Changeset.for_update(:update, %{role: role})
    |> Ash.update(actor: actor)
  end

  defp open_catalog(socket, spec, record) do
    ref_resources =
      spec.fields
      |> Enum.filter(&(&1.type == :ref))
      |> Enum.map(& &1.resource)
      |> Enum.uniq()

    ref_options =
      Map.new(ref_resources, fn resource ->
        {resource, Catalogs.options(resource, socket.assigns.actor)}
      end)

    socket
    |> assign(:catalog_spec, spec)
    |> assign(:catalog_form, Catalogs.form(spec, record, socket.assigns.actor))
    |> assign(:catalog_ref_options, ref_options)
    |> assign(:journal_filter, "")
    |> assign(:admin_view, nil)
    |> assign(:hub, nil)
  end

  # Форма документа без табличной части (кадровые, начисление, выплата):
  # редактор тот же, что у справочников.
  # Начисление зарплаты не заполняется руками: ведомость строится по
  # работающим сотрудникам. Остальные документы открываются формой.
  defp open_document_form(socket, "Начисления зарплаты сотрудникам организаций") do
    open_accrual(socket)
  end

  defp open_document_form(socket, title) do
    spec = Documents.form_spec(title)

    socket
    |> open_form(spec, Catalogs.form(spec, nil, socket.assigns.actor))
    |> assign(:hub, nil)
  end

  defp open_accrual(socket) do
    actor = socket.assigns.actor
    today = Date.utc_today()
    period = %Date{year: today.year, month: today.month, day: 1}

    case Pulse.Payroll.Accruals.build(actor.organization_id, actor, today, period) do
      {:ok, accrual} ->
        record = Pulse.Payroll.Accruals.load(accrual.id, actor.organization_id)

        socket
        |> assign(:document_spec, Documents.spec("Начисления зарплаты сотрудникам организаций"))
        |> assign(:document_record, record)
        |> assign(:hub, nil)
        |> put_toast("Ведомость заполнена по работающим сотрудникам")

      {:error, errors} when is_list(errors) ->
        put_toast(socket, "Не удалось заполнить: #{Enum.join(errors, "; ")}")

      {:error, error} ->
        put_toast(socket, "Не удалось заполнить ведомость: #{Exception.message(error)}")
    end
  end

  # Форма документа без табличной части (кадровые, выплата): редактор
  # тот же, что у справочников.
  defp open_form(socket, spec, form) do
    form = apply_form_defaults(form, Map.get(spec, :defaults, %{}))

    ref_resources =
      spec.fields
      |> Enum.filter(&(&1.type == :ref))
      |> Enum.map(& &1.resource)
      |> Enum.uniq()

    ref_options =
      Map.new(ref_resources, fn resource ->
        {resource, Catalogs.options(resource, socket.assigns.actor)}
      end)

    socket
    |> assign(:catalog_spec, spec)
    |> assign(:catalog_form, form)
    |> assign(:catalog_ref_options, ref_options)
    |> assign(:journal_filter, "")
    |> assign(:admin_view, nil)
    |> assign(:hub, nil)
  end

  defp apply_form_defaults(form, defaults) when map_size(defaults) == 0, do: form

  defp apply_form_defaults(form, defaults) do
    params = Map.new(defaults, fn {key, value} -> {to_string(key), to_string(value)} end)
    AshPhoenix.Form.validate(form, params)
  end

  # Переключение на вкладку из URL. Если вкладки нет в состоянии (например,
  # ссылка открыта в новой сессии), она открывается по идентификатору
  # `раздел|заголовок`.
  defp assign_tab_active(socket, tab_id) do
    if Enum.any?(socket.assigns.tabs, &(&1.id == tab_id)) do
      socket
      |> assign(:active_id, tab_id)
      |> persist_workspace()
    else
      open_tab_by_id(socket, tab_id)
    end
  end

  defp open_tab_by_id(socket, tab_id) do
    case String.split(tab_id, "|", parts: 2) do
      [section_id, title] -> open_tab(socket, section_id, title)
      _ -> socket
    end
  end

  defp open_tab(socket, section_id, title) do
    section_atom = String.to_existing_atom(section_id)
    kind = Menu.kind(section_atom, title)
    group = group_of(Menu.get(section_atom) || Menu.get(:main), title)
    id = "#{section_id}|#{title}"

    tabs =
      if Enum.any?(socket.assigns.tabs, &(&1.id == id)) do
        socket.assigns.tabs
      else
        socket.assigns.tabs ++
          [%{id: id, title: title, kind: kind, group: group, section: section_atom}]
      end

    socket
    |> assign(:tabs, tabs)
    |> assign(:active_id, id)
    |> persist_workspace()
  rescue
    ArgumentError -> socket
  end

  defp active_tab(%{tabs: tabs, active_id: active_id}) do
    Enum.find(tabs, List.first(tabs), &(&1.id == active_id))
  end

  defp hub_section(section_id) do
    section_id
    |> String.to_existing_atom()
    |> Menu.get()
  end

  defp section_for(%{section: nil}), do: Menu.get(:main)

  defp section_for(%{section: section_id}) do
    Menu.get(section_id) || Menu.get(:main)
  end

  defp restore_tabs([]), do: [@home_tab]

  defp restore_tabs(tabs) do
    tabs
    |> Enum.map(&atomize_tab/1)
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> [@home_tab]
      list -> list
    end
  end

  defp atomize_tab(%{"id" => "home"}), do: @home_tab

  defp atomize_tab(%{"id" => id, "title" => title} = raw) do
    %{
      id: id,
      title: title,
      kind: String.to_existing_atom(raw["kind"] || "journal"),
      group: raw["group"] || "",
      section: raw["section"] && String.to_existing_atom(raw["section"])
    }
  rescue
    ArgumentError -> nil
  end

  defp atomize_tab(_), do: nil

  defp persist_workspace(socket) do
    tabs =
      Enum.map(socket.assigns.tabs, fn tab ->
        tab
        |> Map.take([:id, :title, :kind, :group, :section])
        |> Map.new(fn {k, v} -> {to_string(k), to_string(v)} end)
      end)

    favorites = MapSet.to_list(socket.assigns.favorites)

    Pulse.Accounts.save_workspace(socket.assigns.workspace, socket.assigns.current_user, %{
      tabs: tabs,
      active_tab: socket.assigns.active_id,
      favorites: favorites,
      active_organization_id: socket.assigns.actor.organization_id
    })

    socket
  end

  defp put_toast(socket, message) do
    if socket.assigns[:toast_timer], do: Process.cancel_timer(socket.assigns.toast_timer)

    timer = Process.send_after(self(), :clear_toast, 2200)
    assign(socket, toast: message, toast_timer: timer)
  end

  @impl true
  def handle_info(:clear_toast, socket) do
    {:noreply, assign(socket, :toast, nil)}
  end

  defp favorite_items(favorites) do
    favorites
    |> MapSet.to_list()
    |> Enum.flat_map(&favorite_item/1)
    |> Enum.sort()
  end

  defp favorite_item(key) do
    [section_id, title] = String.split(key, "|", parts: 2)
    section = Menu.get(String.to_existing_atom(section_id))

    if section && Menu.find_item(section.id, title) do
      [{section_id, group_of(section, title), title}]
    else
      []
    end
  end

  defp group_of(section, title) do
    Enum.find_value(section.groups, "", fn group ->
      if Enum.any?(group.items, &(&1.title == title)), do: group.title
    end)
  end

  defp journal_rows(tab) do
    seed = :erlang.phash2(tab.id)

    :rand.seed(:exsss, {seed, seed + 1, seed + 2})

    count = 6 + :rand.uniform(5)

    for i <- 0..(count - 1) do
      %{
        id: "#{tab.id}-#{i}",
        date: "#{String.pad_leading("#{20 - i * 2}", 2, "0")}.10.2026",
        no: String.pad_leading("#{count - i + 10}", 6, "0"),
        who: Enum.random(@counterparties),
        wh: "Основной склад",
        sum: :rand.uniform(900_000) + 15_000,
        status: if(:rand.uniform() > 0.25, do: :posted, else: :draft),
        comment: ""
      }
    end
  end

  # Демонстрационный результат для отчётов, которые ещё не реализованы
  # (этапы 5+). Формат совпадает с настоящими отчётами.
  defp demo_report do
    rows =
      @counterparties
      |> Enum.take(4)
      |> Enum.map(fn name ->
        opening = :rand.uniform(3_000_000)
        income = :rand.uniform(2_000_000)
        outcome = :rand.uniform(2_000_000)

        %{
          name: name,
          opening: opening,
          income: income,
          outcome: outcome,
          closing: opening + income - outcome
        }
      end)

    totals =
      Enum.reduce(rows, %{opening: 0, income: 0, outcome: 0, closing: 0}, fn row, acc ->
        %{
          opening: acc.opening + row.opening,
          income: acc.income + row.income,
          outcome: acc.outcome + row.outcome,
          closing: acc.closing + row.closing
        }
      end)

    %{
      columns: ["Показатель", "Начальное сальдо", "Приход", "Расход", "Конечное сальдо"],
      rows:
        Enum.map(rows, fn row ->
          [
            row.name,
            money(row.opening),
            money(row.income),
            money(row.outcome),
            money(row.closing)
          ]
        end),
      totals: [
        "Итого",
        money(totals.opening),
        money(totals.income),
        money(totals.outcome),
        money(totals.closing)
      ]
    }
  end

  defp icon_style(hue), do: PulseWeb.DesignTokens.section_icon_style(hue)

  defp initial(email) when is_binary(email) do
    email
    |> String.first()
    |> String.upcase()
  end

  defp initial(_), do: "?"

  defp format_today do
    "20 октября 2026"
  end
end
