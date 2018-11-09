FROM alpine:3.8

RUN apk add --no-cache nginx-mod-http-lua

env PLEROMA_CONTAINER bee2-unknown-host

# Create folder for PID file
RUN mkdir -p /run/nginx

# Add our nginx conf
COPY ./nginx.conf /etc/nginx/nginx.conf

VOLUME ["/var/log/nginx", "/tmp/pleroma-media-cache"]

CMD ["nginx"]
