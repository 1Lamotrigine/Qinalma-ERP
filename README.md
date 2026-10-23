# Qinalma ERP

ERP-платформа для малого бизнеса Казахстана. Elixir/Phoenix + Ash.

Техническое имя приложения — `pulse` (модули `Pulse.*`).

## Требования

Docker или Podman (команды те же, замените `docker compose` на
`podman compose`). Локально устанавливать Postgres, Erlang и Elixir
не нужно — всё работает в контейнерах.

Для разработки на хосте (быстрый live reload) дополнительно нужны
Erlang/OTP 29.1.2 и Elixir 1.20.4 — версии закреплены в `.tool-versions`
(mise или asdf).

## Быстрый старт

```bash
cp .env.example .env
# задайте DB_PASSWORD, SECRET_KEY_BASE, TOKEN_SIGNING_SECRET в .env

docker compose up -d --build
```

Приложение поднимется на <http://localhost:4000>. При первом запуске
контейнер `web` сам накатывает миграции и создаёт администратора:

- email: `ADMIN_EMAIL` из `.env` (по умолчанию `admin@qinalma.local`)
- пароль: `ADMIN_PASSWORD` из `.env` (по умолчанию `admin12345678`)

Сгенерировать секреты:

```bash
mix phx.gen.secret                       # SECRET_KEY_BASE
openssl rand -hex 32                     # TOKEN_SIGNING_SECRET
```

## Ежедневные команды

```bash
docker compose up -d --build                  # БД + приложение (пересобирает образ)
docker compose logs -f web                    # логи приложения
docker compose ps                             # состояние контейнеров
docker compose --profile tools up -d --build  # + pgAdmin на http://localhost:5050
docker compose exec db psql -U pulse -d pulse_dev   # консоль SQL
docker compose exec web bin/pulse remote      # IEx внутри контейнера
docker compose down                           # остановить
docker compose down -v                        # остановить и стереть данные
```

> **Образ `web` не пересобирается сам.** `docker compose up -d` пересобирает образ
> только если его нет локально: при наличии тега `pulse_web:latest` поднимется
> старая сборка. После правок в `lib/`, `priv/` или `config/` добавляйте `--build`
> (или выполняйте `docker compose build web`). Если интерфейс ведёт себя не так,
> как код, — первым делом пересоберите образ.
>
> **Стили.** Ассеты собираются внутри образа (`mix assets.deploy`), локальные
> `priv/static/assets` и `_build` в контекст не попадают — за это отвечает
> `.dockerignore`. Если стили выглядят сломанными, проверьте в браузере, что
> загружается свежий диджест `app-<хеш>.css`, и пересоберите образ с `--build`.

Бэкап:

```bash
docker compose exec -T db pg_dump -U pulse -Fc pulse_dev > backups/pulse.dump
```

## Разработка на хосте

БД — в контейнере, Phoenix — на хосте, ради мгновенной перекомпиляции:

```bash
docker compose up -d db
mix deps.get
mix ash.setup
mix phx.server
```

`.env` читается автоматически в dev-режиме.

## Качество

```bash
mix test
mix format --check-formatted
mix credo --strict
mix sobelow
mix dialyzer
```

Всё это проверяется в CI (`.github/workflows/ci.yml`), плюс сборка
Docker-образа и проверка, что `docker compose up -d` отвечает на `/`.

## Структура

```
lib/pulse/          доменный слой (Ash)
  accounts/         пользователи и аутентификация
  repo.ex, release.ex
lib/pulse_web/      веб-слой (Phoenix/LiveView)
  live/             LiveView
  controllers/      контроллеры
  components/       компоненты
priv/repo/          миграции и сиды
docker/             файлы для контейнеров
rel/                скрипты релиза
```

## Документация

Проектная документация — в каталоге `../md_files/`:
ТЗ и архитектура, файлы этапов 0–10.
