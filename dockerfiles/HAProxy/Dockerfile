FROM haproxy:1.7.9

RUN apt-get -y update
RUN apt-get -y install python

COPY haproxy-config.py /
COPY startup /
RUN chmod 700 /haproxy-config.py
RUN chmod 700 /startup


RUN mkdir -p /etc/letsencrypt/live
COPY dummy.pem /usr/local/etc/haproxy/

ENTRYPOINT ["/startup"]
CMD ["haproxy", "-f", "/usr/local/etc/haproxy/haproxy.cfg"]
