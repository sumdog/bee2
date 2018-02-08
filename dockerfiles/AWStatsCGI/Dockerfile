FROM httpd

RUN apt-get update -y && \
    apt-get install -y awstats

COPY httpd.conf /usr/local/apache2/conf/httpd.conf

RUN  mkdir -p  /usr/local/apache2/htdocs/stats

RUN ln -s /usr/lib/cgi-bin/awstats.pl /usr/local/apache2/htdocs/stats
RUN ln -s ln -s /usr/share/awstats/icon /usr/local/apache2/htdocs/stats
RUN sed -i "s/\/etc\/opt\/awstats/\/awstats\/config/g" /usr/lib/cgi-bin/awstats.pl
RUN rm -f /etc/awstats/awstats.conf

EXPOSE 8080
