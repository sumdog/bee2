#!/bin/sh

set -e
set -x

cp -rvf /pleroma/custom/* /pleroma/priv/static || true
touch /docker-config.exs

mix deps.get
mix ecto.migrate
exec mix phx.server
