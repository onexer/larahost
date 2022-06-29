FROM ubuntu:21.10

LABEL maintainer="Humaid Al Mansoori"

ENV DEBIAN_FRONTEND noninteractive
ENV TZ=UTC

ARG PHP_VERSION
ENV PHP_VERSION ${PHP_VERSION:-8.1}
ARG DevelopmentBuild
ENV DevelopmentBuild ${DevelopmentBuild:-"false"}

RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# update and upgrade all packages
RUN apt update && apt upgrade -y

# install base packages
RUN apt-get install -y gnupg nano gosu curl ca-certificates zip unzip git supervisor sqlite3 libcap2-bin libpng-dev nginx \
    cron rsync iputils-ping wget python2 software-properties-common mysql-client postgresql-client


# MSSQL
RUN curl https://packages.microsoft.com/keys/microsoft.asc | apt-key add -
RUN curl https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/prod.list > /etc/apt/sources.list.d/mssql-release.list
RUN exit
RUN apt-get update
RUN ACCEPT_EULA=Y apt-get install -y msodbcsql18 && ACCEPT_EULA=Y apt-get install -y mssql-tools18 && apt-get install -y unixodbc-dev



## PHP
RUN add-apt-repository ppa:ondrej/php -y
RUN apt-get update
RUN apt-get install php$PHP_VERSION php$PHP_VERSION-dev php$PHP_VERSION-cli php$PHP_VERSION-fpm php$PHP_VERSION-xml -y --allow-unauthenticated
RUN apt-get install -y  \
    php$PHP_VERSION-pgsql php$PHP_VERSION-sqlite3  \
    php$PHP_VERSION-gd php$PHP_VERSION-imagick php$PHP_VERSION-curl \
    php$PHP_VERSION-imap php$PHP_VERSION-mysql php$PHP_VERSION-mbstring \
    php$PHP_VERSION-xml php$PHP_VERSION-zip php$PHP_VERSION-bcmath php$PHP_VERSION-soap \
    php$PHP_VERSION-intl php$PHP_VERSION-readline \
    php$PHP_VERSION-ldap \
    php$PHP_VERSION-msgpack php$PHP_VERSION-igbinary php$PHP_VERSION-redis php$PHP_VERSION-swoole \
    php$PHP_VERSION-memcached php$PHP_VERSION-pcov

RUN if [ "$DevelopmentBuild" = "true" ] ; then apt-get install -y php$PHP_VERSION-xdebug; fi

RUN setcap "cap_net_bind_service=+ep" /usr/bin/php$PHP_VERSION


RUN pecl config-set php_ini /etc/php/$PHP_VERSION/fpm/php.ini \
    && pecl install sqlsrv \
    && pecl install pdo_sqlsrv \
    && printf "; priority=20\nextension=sqlsrv.so\n" > /etc/php/$PHP_VERSION/mods-available/sqlsrv.ini \
    && printf "; priority=30\nextension=pdo_sqlsrv.so\n" > /etc/php/$PHP_VERSION/mods-available/pdo_sqlsrv.ini \
    && exit

RUN phpenmod sqlsrv pdo_sqlsrv

# install composer
RUN php -r "readfile('https://getcomposer.org/installer');" | php -- --install-dir=/usr/bin/ --filename=composer

# install nodejs/npm/yarn
RUN curl -sLS https://deb.nodesource.com/setup_16.x | bash - \
    && apt-get install -y nodejs \
    && npm install -g npm \
    && apt-get install -y yarn


# update and upgrade all packages
RUN apt update && apt upgrade -y

# clean up
RUN apt-get -y autoremove \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# create docker user
RUN groupadd --force -g 1337 docker
RUN useradd -ms /bin/bash --no-user-group -g 1337 -u 1337 docker
RUN mkdir /home/docker/packages
RUN mkdir /home/docker/www
RUN mkdir /home/docker/www/public
VOLUME ["/home/docker/www"]
WORKDIR /home/docker/www

# copy files
COPY config/php/fpm-docker.conf /etc/php/$PHP_VERSION/fpm/pool.d/www.conf
COPY config/supervisor/supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY config/nginx/nginx.conf /etc/nginx/nginx.conf
COPY config/nginx/docker.conf /etc/nginx/conf.d/docker.conf
COPY config/nginx/index.php /home/docker/www/public/index.php
COPY config/composer/composer.json /home/docker/.config/composer/config.json


# crontab
RUN echo "* * * * * docker cd /home/docker/www && php artisan schedule:run >> /dev/null 2>&1" > /etc/cron.d/docker
RUN chmod 0644 /etc/cron.d/docker

# copy and change start script
COPY config/start-container /usr/local/bin/start-container
RUN chmod +x /usr/local/bin/start-container

ENTRYPOINT ["start-container"]


