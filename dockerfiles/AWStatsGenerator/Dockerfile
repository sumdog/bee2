FROM ubuntu

RUN apt-get update -y && \
    apt-get install -y awstats python3 \
    libnet-ip-perl libnet-dns-perl xz-utils

RUN rm -f /etc/awstats/awstats.conf
RUN sed -i "s/\/etc\/opt\/awstats/\/awstats\/config/g" /usr/lib/cgi-bin/awstats.pl

COPY generate.py /
RUN chmod 700 /generate.py

ENTRYPOINT ["/generate.py"]
