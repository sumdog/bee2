FROM elixir:1.7.4-alpine

ENV POSTGRES_IP 127.0.0.1
ENV POSTGRES_DB pleroma
ENV POSTGRES_USER pleroma
ENV POSTGRES_PASSWORD pleroma
ENV DB_POOL_SIZE int:16
ENV MIX_ENV prod
ENV PLEROMA_VERSION develop
ENV PLEROMA_LOGLEVEL info
ENV PLEROMA_URL example.com
ENV PLEROMA_SCHEME https
ENV PLEROMA_PORT int:443
ENV PLEROMA_SECRET_KEY_BASE changeme
ENV PLEROMA_NAME string:coolInstance
ENV PLEROMA_ADMIN_EMAIL admin@example.com
ENV PLEROMA_MAX_NOTICE_CHARS int:500
ENV PLEROMA_REGISTRATIONS_OPEN bool:true
ENV PLEROMA_MEDIA_PROXY_ENABLED bool:false
ENV PLEROMA_MEDIA_PROXY_URL string:https://cdn.example.com
ENV PLEROMA_MEDIA_PROXY_REDIRECT_ON_FAILURE bool:true
ENV PLEROMA_CHAT_ENABLED bool:true
ENV PLEROMA_DESCRIPTION Instance description
ENV PLEROMA_FEDERATING true
ENV PLEROMA_FE_THEME "pleroma-dark"
ENV PLEROMA_FE_LOGO "/static/logo.png"
ENV PLEROMA_FE_BACKGROUND "/static/aurora_borealis.jpg"
ENV PLEROMA_FE_REDIRECT_NO_LOGIN "/main/all"
ENV PLEROMA_FE_REDIRECT_LOGIN "/main/friends"
ENV PLEROMA_FE_SHOW_INSTANCE_PANEL true
ENV PLEROMA_FE_SCOPE_OPTIONS_ENABLED false

ENV UID=911 GID=911 \
    MIX_ENV=prod

ARG PLEROMA_VER=develop

RUN apk -U upgrade \
    && apk add --no-cache \
       build-base \
       git

RUN addgroup -g ${GID} pleroma \
    && adduser -h /pleroma -s /bin/sh -D -G pleroma -u ${UID} pleroma

USER pleroma
WORKDIR pleroma

# Bust the build cache
# ARG __BUST_CACHE
# ENV __BUST_CACHE $__BUST_CACHE

RUN git clone -b develop https://git.pleroma.social/pleroma/pleroma.git /pleroma \
    && git checkout ${PLEROMA_VER}

# Config helper
COPY --chown=pleroma:pleroma ./docker-config.exs /docker-config.exs
RUN \
       ln -s /docker-config.exs config/prod.secret.exs \
    && ln -s /docker-config.exs config/dev.secret.exs

RUN mix local.rebar --force \
    && mix local.hex --force \
    && mix deps.get \
    && mix compile

COPY --chown=pleroma:pleroma styles.json /pleroma/priv/static/static/styles.json

RUN mkdir /pleroma/uploads
RUN mkdir /pleroma/custom

VOLUME ["/pleroma/custom", "/pleroma/uploads"]

# Register pseudo-entrypoint
COPY entrypoint.sh /pleroma/entrypoint.sh
CMD "/pleroma/entrypoint.sh"
