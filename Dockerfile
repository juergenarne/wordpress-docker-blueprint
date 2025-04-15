FROM php:8.4-apache

# Install required PHP extensions
RUN apt-get update && apt-get install -y \
    libpng-dev \
    libjpeg-dev \
    libfreetype6-dev \
    libzip-dev \
    libicu-dev \
    libmagickwand-dev --no-install-recommends \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-configure intl \
    && docker-php-ext-install gd mysqli zip intl exif \
    && pecl install imagick \
    && docker-php-ext-enable imagick

# Enable Apache mod_rewrite for WordPress permalinks
RUN a2enmod rewrite
