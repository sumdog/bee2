FROM roundcube/roundcubemail

# The official roundcube image doesn't support changing ports
# It's based off of php:7.0-apache, so I found this workaround here:
# https://github.com/docker-library/php/issues/94#issuecomment-320695125

RUN sed -i "s/80/8080/g" /etc/apache2/sites-available/000-default.conf /etc/apache2/ports.conf

EXPOSE 8080
