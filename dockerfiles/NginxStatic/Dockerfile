FROM nginx:1.13.6

COPY nginx.conf /etc/nginx/nginx.conf
RUN chown -R nginx:nginx /var/log/nginx

EXPOSE 8080

VOLUME ["/var/log/nginx", "/var/www"]
