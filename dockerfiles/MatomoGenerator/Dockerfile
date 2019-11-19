FROM alpine:3.10.3


RUN apk update && \
    apk add python python3 xz

ARG MATOMO_VER=3.12.0

RUN wget https://builds.matomo.org/matomo-$MATOMO_VER.tar.gz
RUN tar xvfz matomo-$MATOMO_VER.tar.gz \
    --strip-components=3 \
    -C /usr/local/bin \
    matomo/misc/log-analytics/import_logs.py

ENV LOG_PATH /weblogs
ENV ROTATE_PATH /weblogs/processed
ENV NGINX_CONTAINER unknown-container
ENV LOG_CONFIG 1:example.org.log,2:example.com.log

ENV MATOMO_URL http://localhost
ENV MATOMO_TOKEN tokennotset

COPY process_logs.py /usr/local/bin/process_logs
RUN chmod 755 /usr/local/bin/process_logs

CMD ["process_logs"]
