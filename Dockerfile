ARG PHP_VERSION=8.5.12
FROM php:${PHP_VERSION}-apache

# Install msmtp as lightweight sendmail replacement
RUN apt-get update && \
    apt-get install -y msmtp msmtp-mta \
    libpng-dev \
    libjpeg62-turbo-dev \
    libfreetype6-dev \
    libzip-dev \
    libicu-dev \
    libmagickwand-dev \
    imagemagick \
    unzip \
    git \
    mariadb-client \
    --no-install-recommends \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-configure intl \
    && docker-php-ext-install gd mysqli zip intl exif \
    && if ! pecl list | grep imagick; then pecl install imagick; fi \
    && docker-php-ext-enable imagick \
    && if ! php -m | grep -i redis; then pecl install redis && docker-php-ext-enable redis; fi \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Enable Apache mod_rewrite for WordPress permalinks
RUN a2enmod rewrite

# Take the client IP from the reverse proxy (nginx on the host)
RUN a2enmod remoteip \
    && printf 'RemoteIPHeader X-Forwarded-For\nRemoteIPTrustedProxy 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16\n' \
       > /etc/apache2/conf-available/remoteip.conf \
    && a2enconf remoteip

# Install WP-CLI
RUN curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
    && chmod +x wp-cli.phar \
    && mv wp-cli.phar /usr/local/bin/wp

# Link msmtp to sendmail path
RUN ln -sf /usr/bin/msmtp /usr/sbin/sendmail

# /etc/msmtprc is mounted at runtime (see docker-compose.yml)
RUN echo 'sendmail_path = "/usr/bin/msmtp -t --read-envelope-from"' > /usr/local/etc/php/conf.d/mail.ini

RUN touch /var/log/msmtp.log && \
    chown www-data:www-data /var/log/msmtp.log && \
    chmod 644 /var/log/msmtp.log
