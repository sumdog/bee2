FROM php:7.2.2-apache-stretch

ENV SIMPLEID_VERSION 1.0.2
ENV DOMAIN openid.example.com
ENV APP_DIR /var/www/html

# Apache Setup
RUN a2enmod rewrite
RUN sed -i "s/80/8080/g" /etc/apache2/ports.conf
COPY 000-default.conf /etc/apache2/sites-available/000-default.conf
EXPOSE 8080

# PHP Extensions
RUN docker-php-ext-install bcmath
RUN apt-get update && apt-get install -y libgmp-dev \
    && docker-php-ext-install gmp \
    && rm -rf /var/lib/apt/lists/*

# State
RUN mkdir -p /simpleid/identities
RUN mkdir -p /simpleid/cache
RUN mkdir -p /simpleid/store
VOLUME ["/simpleid"]

# SimpleID
WORKDIR /opt
RUN mkdir simpleid
RUN curl -L https://downloads.sourceforge.net/project/simpleid/simpleid/$SIMPLEID_VERSION/simpleid-$SIMPLEID_VERSION.tar.gz -o r.tgz
RUN tar xfz r.tgz
RUN mv simpleid/www/.htaccess.dist $APP_DIR/.htaccess
RUN mv simpleid/www/* $APP_DIR
COPY config.php $APP_DIR

# Cleanup
RUN rm -rf /opt/simpleid
RUN rm -rf /opt/r.tgz
