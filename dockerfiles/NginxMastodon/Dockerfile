FROM alpine:3.8

RUN apk add --no-cache nginx-mod-http-lua

env MASTODON_WEB_CONTAINER bee2-unknown-host
env MASTODON_STREAMING_CONTAINER bee2-unknown-host

# Create folder for PID file
RUN mkdir -p /run/nginx

# Add our nginx conf
COPY ./nginx.conf /etc/nginx/nginx.conf

CMD ["nginx"]
