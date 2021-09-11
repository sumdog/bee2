FROM alpine:3.13.6

RUN apk update && \
    apk add opensmtpd supervisor certbot dkimproxy clamav-libunrar spamassassin \
    dovecot-pgsql dovecot perl-mail-spamassassin freshclam clamsmtp clamav-daemon opensmtpd-table-passwd && \
    apk add fdm --repository=http://dl-cdn.alpinelinux.org/alpine/edge/testing


# SpamPD in alpine repo is out of date
RUN wget https://github.com/mpaperno/spampd/archive/refs/tags/2.61.tar.gz
RUN tar xvfz 2.61.tar.gz
RUN rm 2.61.tar.gz

COPY spamassassin-local.cf /etc/mail/spamassassin/local.cf

COPY supervisor.conf /etc/supervisord.conf
COPY crontab /var/spool/cron/crontabs/root

COPY lineinfile /usr/share/misc/lineinfile

RUN adduser -h /mail/spool -s /bin/false -D -u 2000 -g 2000 vmail

VOLUME ["/mail"]

STOPSIGNAL SIGTERM

COPY startup /
RUN chmod 755 /startup

CMD ["/startup"]
