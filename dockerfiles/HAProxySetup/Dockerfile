FROM python:3

ENV CERTBOT_CONTAINER bee2-app-certbot
ENV AWSTATS_CONTAINER disabled
ENV DOMAINS example.com

VOLUME ["/etc/haproxy", "/etc/letsencrypt"]

WORKDIR /usr/src/app

COPY dummy.pem .
COPY haproxy-config.py .
RUN chmod 700 haproxy-config.py
CMD [ "python", "./haproxy-config.py" ]
