# Многоступенчатая сборка приложения Qinalma ERP.
#
# Стадии:
#   builder  — установка зависимостей, компиляция ассетов, сборка релиза
#   prod     — минимальный рантайм с релизом и автозапуском миграций
#
# Версии зафиксированы под Erlang/OTP 29 и Elixir 1.20.

ARG ELIXIR_VERSION=1.20.4
ARG OTP_VERSION=29.1.2
ARG DEBIAN_VERSION=bookworm-20261005

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}-slim"
ARG RUNNER_IMAGE="debian:${DEBIAN_VERSION}-slim"

# ---------------------------------------------------------------------------
# Стадия сборки
# ---------------------------------------------------------------------------
FROM ${BUILDER_IMAGE} AS builder

RUN apt-get update -y \
  && apt-get install -y --no-install-recommends build-essential git curl ca-certificates \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

# Устанавливаем Node.js для сборки ассетов
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
  && apt-get install -y --no-install-recommends nodejs \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /app

ENV MIX_ENV="prod"

# Сначала зависимости — так слой кэшируется между сборками
RUN mix local.hex --force && mix local.rebar --force

COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

COPY priv priv
COPY lib lib
COPY assets assets
COPY rel rel

# Сборка ассетов. Алиас сам компилирует проект: Tailwind сканирует
# colocated CSS из `_build/prod/phoenix-colocated`, который появляется
# при компиляции.
RUN mix assets.deploy

# runtime-конфигурация и релиз
COPY config/runtime.exs config/
RUN mix release

# ---------------------------------------------------------------------------
# Стадия рантайма
# ---------------------------------------------------------------------------
FROM ${RUNNER_IMAGE} AS prod

RUN apt-get update -y \
  && apt-get install -y --no-install-recommends libstdc++6 openssl libncurses6 locales ca-certificates curl \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

# Русская локаль для корректных форматов
RUN sed -i '/ru_RU.UTF-8/s/^# //g' /etc/locale.gen 2>/dev/null || true \
  && locale-gen

ENV LANG="ru_RU.UTF-8" \
    LANGUAGE="ru_RU:ru" \
    LC_ALL="ru_RU.UTF-8"

WORKDIR /app

RUN chown nobody /app

ENV MIX_ENV="prod" \
    PHX_SERVER="true"

COPY --from=builder --chown=nobody:root /app/_build/prod/rel/pulse ./

USER nobody

EXPOSE 4000

CMD ["/app/bin/migrate_and_start"]
