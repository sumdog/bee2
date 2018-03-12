FROM alpine
MAINTAINER sumit@penguindreams.org

ENV NGINX_CONTAINER bee2-app-nginx-static

VOLUME ["/weblogs"]

RUN apk --update add logrotate python3 xz
ADD rotate /rotate
RUN chmod 700 /rotate

CMD ["/rotate"]
