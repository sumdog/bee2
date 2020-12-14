FROM alpine

ENV VPN_SUBNET 10.0.0.0/16
ENV GATEWAY 127.0.0.1
ENV LISTEN_PORT 80
ENV REMOTE_ADDR 127.0.0.1:8080

RUN apk update && \
    apk add socat tini

COPY service /service
RUN chmod 700 /service

ENTRYPOINT ["/sbin/tini", "--"]
CMD '/service'