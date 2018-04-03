FROM php:7.2.2-cli-stretch

RUN apt-get update && apt-get install libicu-dev -y git
# PHP Extensions
RUN apt-get update && apt-get install -y postgresql-server-dev-all \
   && docker-php-ext-install pgsql pdo pdo_pgsql intl pcntl \
   && rm -rf /var/lib/apt/lists/*

WORKDIR /opt
RUN git clone https://tt-rss.org/git/tt-rss.git tt-rss
RUN ln -s /usr/local/bin/php /usr/bin/php

COPY config.php /opt/tt-rss
RUN mkdir -p /state/lock
RUN mkdir -p /state/cache
#RUN chmod 777 /opt/tt-rss/feed-icons
VOLUME ['/state']

RUN useradd -ms /bin/bash ttrss
USER ttrss

CMD php /opt/tt-rss/update_daemon2.php
