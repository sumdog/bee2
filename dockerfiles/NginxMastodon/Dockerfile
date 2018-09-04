FROM alpine:3.8

RUN apk add --no-cache nginx-mod-http-lua

env MASTODON_WEB_CONTAINER bee2-unknown-host
env MASTODON_STREAMING_CONTAINER bee2-unknown-host
env MAINTENANCE_MODE false

# Create folder for PID file
RUN mkdir -p /run/nginx

# Add our nginx conf
COPY ./nginx.conf /etc/nginx/nginx-standard.conf

# Maintenance files
RUN mkdir -p /www
COPY ./maintenance.html /www/maintenance.html
COPY ./nginx-maintenance.conf /etc/nginx/nginx-maintenance.conf

VOLUME ["/var/log/nginx"]

COPY launcher.sh /launcher.sh
RUN chmod 700 /launcher.sh
CMD ["/launcher.sh"]
