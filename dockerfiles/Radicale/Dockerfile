FROM python:3

ARG VERSION=3.0.4
RUN pip install pytz passlib bcrypt radicale==$VERSION

ENV RADICALE_CONFIG /etc/radicale/config
RUN mkdir -p /etc/radicale
COPY config $RADICALE_CONFIG

VOLUME /radicale
EXPOSE 8080

CMD ["radicale"]
