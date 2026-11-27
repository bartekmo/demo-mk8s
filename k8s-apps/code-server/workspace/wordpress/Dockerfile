# 1. build WordPress from this source tree (npm + grunt -> build/)
FROM node:24 AS build
WORKDIR /src
COPY package.json package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY . .
RUN npm run build

# 2. plugins shipped with the image (configured by the "wordpress" chart):
#    OpenID Connect Generic - login via authentik
FROM alpine:3 AS plugins
ARG OIDC_PLUGIN_VERSION=3.11.5
ADD https://downloads.wordpress.org/plugin/daggerhart-openid-connect-generic.${OIDC_PLUGIN_VERSION}.zip /tmp/oidc.zip
RUN mkdir /plugins && unzip -q /tmp/oidc.zip -d /plugins

# 3. runtime: official WordPress image (Apache + PHP + DB-from-env config),
#    with its WordPress replaced by the one built above. The entrypoint copies
#    /usr/src/wordpress into the web root and writes wp-config.php from
#    wp-config-docker.php (WORDPRESS_DB_* environment variables).
FROM wordpress:php8.3-apache
RUN find /usr/src/wordpress -mindepth 1 -maxdepth 1 ! -name wp-config-docker.php -exec rm -rf {} +
COPY --from=build --chown=www-data:www-data /src/build/ /usr/src/wordpress/
COPY --from=plugins --chown=www-data:www-data /plugins/ /usr/src/wordpress/wp-content/plugins/
