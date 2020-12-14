FROM alpine:3.10

# Source: https://github.com/monokal/docker-tinyproxy

RUN apk add --no-cache \
  bash \
  tinyproxy

COPY run.sh /opt/docker-tinyproxy/run.sh

ENTRYPOINT ["/opt/docker-tinyproxy/run.sh"]