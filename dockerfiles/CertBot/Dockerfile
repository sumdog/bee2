FROM certbot/certbot:latest

ENV DOMAINS example.com example.net
ENV EMAIL noreply@example.com
ENV TEST false
ENV PORT 8080
# 1 Week = 10080 min
ENV RENEW_INTERVAL 10080
ENV HAPROXY_CONTAINER bee2-app-haproxy

EXPOSE 8080

RUN apk update
RUN apk add python3
RUN apk add netcat-openbsd
RUN pip3 install check_docker

COPY certbot-domains.py /opt
RUN chmod 700 /opt/certbot-domains.py

COPY reload-haproxy.sh /opt
RUN chmod 700 /opt/reload-haproxy.sh

ENTRYPOINT /opt/certbot-domains.py
