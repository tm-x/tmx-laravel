FROM alpine:3.8

LABEL maintainer="TMX"

# -- nginx
COPY nginx.sh /tmp

RUN /tmp/nginx.sh

COPY nginx.conf /etc/nginx/nginx.conf
COPY nginx.laravel.conf /etc/nginx/conf.d/default.conf

# -- php-fpm
COPY php-fpm.sh /tmp
COPY docker-php-source /usr/local/bin/
COPY docker-php-ext-* docker-php-entrypoint /usr/local/bin/

RUN /tmp/php-fpm.sh

# -- supervisord
RUN apk add --no-cache supervisor
COPY supervisord.conf /etc/supervisord.conf

EXPOSE 80

