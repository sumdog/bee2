FROM php:7.2.2-apache-stretch

# Apache Setup
RUN a2enmod rewrite
RUN sed -i "s/80/8080/g" /etc/apache2/ports.conf
COPY 000-default.conf /etc/apache2/sites-available/000-default.conf
EXPOSE 8080

RUN apt-get update && apt-get install libicu-dev -y git
# PHP Extensions
RUN apt-get update && apt-get install -y postgresql-server-dev-all \
   && docker-php-ext-install pgsql pdo pdo_pgsql intl \
   && rm -rf /var/lib/apt/lists/*

WORKDIR /opt
RUN git clone https://tt-rss.org/git/tt-rss.git tt-rss

COPY config.php /opt/tt-rss
RUN mkdir -p /state/lock
RUN mkdir -p /state/cache
RUN chmod 777 /opt/tt-rss/feed-icons
VOLUME ['/state']
