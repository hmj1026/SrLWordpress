FROM php:8.2-fpm

# Install dependencies
RUN apt-get update && apt-get install -y \
    libfreetype6-dev \
    libjpeg62-turbo-dev \
    libpng-dev \
    libzip-dev \
    zip \
    unzip \
    sendmail \
    msmtp \
    msmtp-mta \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j$(nproc) \
        gd \
        mysqli \
        pdo \
        pdo_mysql \
        zip \
        bcmath \
        exif \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Install WP-CLI
RUN curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
    && chmod +x wp-cli.phar \
    && mv wp-cli.phar /usr/local/bin/wp

# Install Redis
RUN pecl install redis \
    && pecl clear-cache \
    && docker-php-ext-enable redis

# Enable OPcache explicitly
RUN docker-php-ext-install opcache \
    && docker-php-ext-enable opcache

# Install WordPress
RUN curl -O https://wordpress.org/latest.tar.gz \
    && tar -xzf latest.tar.gz -C /var/www/html --strip-components=1 \
    && rm latest.tar.gz \
    && chown -R www-data:www-data /var/www/html

# Configure sendmail
RUN echo "sendmail_path=/usr/bin/msmtp -t" >> /usr/local/etc/php/conf.d/sendmail.ini

# Copy custom PHP config
COPY php.ini /usr/local/etc/php/conf.d/wordpress.ini

# Create log directory and set permissions
RUN mkdir -p /var/log/php \
    && touch /var/log/php-fpm.log \
    && chown -R www-data:www-data /var/log/php /var/log/php-fpm.log

WORKDIR /var/www/html
