FROM alpine

RUN apk update && \
    apk add curl unzip ncurses postgresql-contrib tini

ARG SOAPBOX_VERSION=1.0.0

RUN adduser --system --shell  /bin/false --home /opt/pleroma pleroma
RUN mkdir -p /etc/pleroma
RUN ln -s /state/etc/config.exs /etc/pleroma/config.exs

VOLUME ["/state"]

USER pleroma
RUN wget 'https://git.pleroma.social/api/v4/projects/2/jobs/artifacts/stable/download?job=amd64-musl' -O /tmp/pleroma.zip
RUN unzip /tmp/pleroma.zip -d /tmp
RUN mv /tmp/release/* /opt/pleroma
RUN rmdir /tmp/release
RUN rm /tmp/pleroma.zip

RUN wget https://gitlab.com/soapbox-pub/soapbox-fe/-/jobs/artifacts/v$SOAPBOX_VERSION/download?job=build-production -O /opt/pleroma/soapbox-fe.zip

COPY startup /startup
ENTRYPOINT ["/sbin/tini", "--"]
CMD '/startup'
