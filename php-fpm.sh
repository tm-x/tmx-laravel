#!/bin/sh

set -e
PHP_VERSION=7.2.8

PHPIZE_DEPS="autoconf \
  dpkg-dev dpkg \
  file \
  g++ \
  gcc \
  libc-dev \
  make \
  pkgconf \
  re2c \
"

apk add --no-cache --virtual .persistent-deps \
	ca-certificates \
	curl \
	tar \
	xz \
	libressl

set -x
addgroup -g 82 -S www-data
adduser -u 82 -D -S -G www-data www-data

PHP_INI_DIR=/usr/local/etc/php
mkdir -p $PHP_INI_DIR/conf.d

PHP_EXTRA_CONFIGURE_ARGS="--enable-fpm --with-fpm-user=www-data --with-fpm-group=www-data --disable-cgi"

PHP_CFLAGS="-fstack-protector-strong -fpic -fpie -O2"
PHP_CPPFLAGS="$PHP_CFLAGS"
PHP_LDFLAGS="-Wl,-O1 -Wl,--hash-style=both -pie"

GPG_KEYS="1729F83938DA44E27BA0F4D3DBDB397470D12172 B1B44D8F021E4E2D6021E995DC9FF8D3EE5AF27F"

PHP_URL="https://secure.php.net/get/php-7.2.8.tar.xz/from/this/mirror"
PHP_ASC_URL="https://secure.php.net/get/php-7.2.8.tar.xz.asc/from/this/mirror"
PHP_SHA256="53ba0708be8a7db44256e3ae9fcecc91b811e5b5119e6080c951ffe7910ffb0f" 
PHP_MD5=""

set -xe
apk add --no-cache --virtual .fetch-deps \
	gnupg \
	wget

mkdir -p /usr/src
cd /usr/src
wget -O php.tar.xz "$PHP_URL"

if [ -n "$PHP_SHA256" ]; then
	echo "$PHP_SHA256 *php.tar.xz" | sha256sum -c -
fi
if [ -n "$PHP_MD5" ]; then
	echo "$PHP_MD5 *php.tar.xz" | md5sum -c -
fi
if [ -n "$PHP_ASC_URL" ]; then 
	wget -O php.tar.xz.asc "$PHP_ASC_URL"
  export GNUPGHOME="$(mktemp -d)"
	for key in $GPG_KEYS; do
		gpg --keyserver ha.pool.sks-keyservers.net --recv-keys "$key"
	done
  gpg --batch --verify php.tar.xz.asc php.tar.xz
  command -v gpgconf > /dev/null && gpgconf --kill all
  rm -rf "$GNUPGHOME"
fi

apk del .fetch-deps

set -xe \
	&& apk add --no-cache --virtual .build-deps \
		$PHPIZE_DEPS \
		coreutils \
		curl-dev \
		libedit-dev \
		libressl-dev \
		libsodium-dev \
		libxml2-dev \
		sqlite-dev

CFLAGS="$PHP_CFLAGS"
CPPFLAGS="$PHP_CPPFLAGS"
LDFLAGS="$PHP_LDFLAGS"

docker-php-source extract
cd /usr/src/php
gnuArch="$(dpkg-architecture --query DEB_BUILD_GNU_TYPE)"
./configure \
  --build="$gnuArch" \
  --with-config-file-path="$PHP_INI_DIR" \
  --with-config-file-scan-dir="$PHP_INI_DIR/conf.d" \
	--enable-option-checking=fatal \
	--with-mhash \
	--enable-ftp \
  --enable-mbstring \
	--enable-mysqlnd \
  --with-sodium=shared \
  --with-curl \
  --with-pdo-mysql \
  --with-libedit \
  --with-openssl \
  --with-zlib \
  $(test "$gnuArch" = 's390x-linux-gnu' && echo '--without-pcre-jit') $PHP_EXTRA_CONFIGURE_ARGS

make -j "$(nproc)"
make install 
{ find /usr/local/bin /usr/local/sbin -type f -perm +0111 -exec strip --strip-all '{}' + || true; }
make clean
	
cd / 
docker-php-source delete
runDeps="$( \
		scanelf --needed --nobanner --format '%n#p' --recursive /usr/local \
			| tr ',' '\n' \
			| sort -u \
			| awk 'system("[ -e /usr/local/lib/" $1 " ]") == 0 { next } { print "so:" $1 }' \
	)"

apk add --no-cache --virtual .php-rundeps $runDeps 
apk del .build-deps
pecl update-channels 
rm -rf /tmp/pear ~/.pearrc

docker-php-ext-enable sodium

set -ex
cd /usr/local/etc
	
if [ -d php-fpm.d ]; then
	sed 's!=NONE/!=!g' php-fpm.conf.default | tee php-fpm.conf > /dev/null;
	cp php-fpm.d/www.conf.default php-fpm.d/www.conf;
else 
	mkdir php-fpm.d;
	cp php-fpm.conf.default php-fpm.d/www.conf;
	{ \
    echo '[global]'; \
    echo 'include=etc/php-fpm.d/*.conf'; \
  } | tee php-fpm.conf;
fi 

{ \
  echo '[global]'; \
  echo 'error_log = /proc/self/fd/2'; \
  echo; \
  echo '[www]'; \
  echo '; if we send this to /proc/self/fd/1, it never appears'; \
  echo 'access.log = /proc/self/fd/2'; \
  echo; \
  echo 'clear_env = no'; \
  echo; \
  echo '; Ensure worker stdout and stderr are sent to the main error log.'; \
  echo 'catch_workers_output = yes'; \
} | tee php-fpm.d/docker.conf \

{ \
  echo '[global]'; \
  echo 'daemonize = no'; \
  echo; \
  echo '[www]'; \
  echo 'listen = 9000'; \
} | tee php-fpm.d/zz-docker.conf

