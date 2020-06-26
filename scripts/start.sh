#!/bin/bash

# Always chown webroot for better mounting
chown -f nginx.nginx /var/www/html

if [ ! -z "$SSH_KEY" ]; then
  mkdir -p -m 0700 /var/cache/nginx/.ssh
  chown nginx.nginx -R /var/cache/nginx
  su -c "echo $SSH_KEY > ~/.ssh/id_rsa.base64" nginx
  su -c "base64 -d ~/.ssh/id_rsa.base64 > ~/.ssh/id_rsa" nginx
  su -c "chmod 600 ~/.ssh/id_rsa" nginx
  # Add git repos to known sites
  su -c "ssh-keyscan -H github.com >> ~/.ssh/known_hosts" nginx
  su -c "ssh-keyscan -H gitlab.com >> ~/.ssh/known_hosts" nginx
fi

# Set custom webroot
if [ ! -z "$WEBROOT" ]; then
  webroot=$WEBROOT
  sed -i "s#root /var/www/html;#root ${webroot};#g" /etc/nginx/sites-available/default.conf
else
  webroot=/var/www/html
fi

# Setup git variables
if [ ! -z "$GIT_EMAIL" ]; then
  su -c "git config --global user.email '$GIT_EMAIL'" nginx
fi
if [ ! -z "$GIT_NAME" ]; then
  su -c "git config --global user.name '$GIT_NAME'" nginx
  su -c "git config --global push.default simple" nginx
fi

# Dont pull code down if the .git folder exists
if [ ! -d "/var/www/html/.git" ]; then
 # Pull down code from git for our site!
 if [ ! -z "$GIT_REPO" ]; then
   # Remove the test index file
   rm -Rf /var/www/html/index.php
   if [ ! -z "$GIT_BRANCH" ]; then
     su -c "git clone -b $GIT_BRANCH $GIT_REPO /var/www/html" nginx
   else
     su -c "git clone $GIT_REPO /var/www/html" nginx
   fi
 fi
fi

# Display PHP error's or not
if [[ "$ERRORS" != "1" ]] ; then
 echo display_errors = Off >> /etc/php7/conf.d/php.ini
else
 echo display_errors = On >> /etc/php7/conf.d/php.ini
fi

# Enable PHP short tag or not
if [[ "$SHORT_TAG" != "1" ]] ; then
 echo short_open_tag = Off >> /etc/php7/conf.d/php.ini
else
 echo short_open_tag = On >> /etc/php7/conf.d/php.ini
fi

# Display Version Details or not
if [[ "$HIDE_NGINX_HEADERS" == "0" ]] ; then
 sed -i "s/server_tokens off;/server_tokens on;/g" /etc/nginx/nginx.conf
else
 sed -i "s/expose_php = On/expose_php = Off/g" /etc/php7/conf.d/php.ini
fi

# Enable proxy for Docker-Hook at /docker-hook/
if [[ "$DOCKER_HOOK_PROXY" != "1" ]] ; then
 sed -i '/location \/docker-hook/,/.*\}/d' /etc/nginx/sites-available/default.conf
 sed -i '/location \/docker-hook/,/.*\}/d' /etc/nginx/sites-available/default-ssl.conf
fi

# Increase the memory_limit
if [ ! -z "$PHP_MEM_LIMIT" ]; then
 sed -i "s/memory_limit = 128M/memory_limit = ${PHP_MEM_LIMIT}M/g" /etc/php7/conf.d/php.ini
fi

# Increase the post_max_size
if [ ! -z "$PHP_POST_MAX_SIZE" ]; then
 sed -i "s/post_max_size = 100M/post_max_size = ${PHP_POST_MAX_SIZE}M/g" /etc/php7/conf.d/php.ini
fi

# Increase the upload_max_filesize
if [ ! -z "$PHP_UPLOAD_MAX_FILESIZE" ]; then
 sed -i "s/upload_max_filesize = 100M/upload_max_filesize= ${PHP_UPLOAD_MAX_FILESIZE}M/g" /etc/php7/conf.d/php.ini
fi

# Set Timezone
if [ ! -z "$TIMEZONE" ]; then
 cp /usr/share/zoneinfo/${TIMEZONE} /etc/localtime
 # PHP7 does not support timzezone automatically
 sed -i "s~;date.timezone =~date.timezone = $TIMEZONE~g" /etc/php7/conf.d/php.ini
fi

# Add Cronjob
if [ ! -z "$CRONJOB" ]; then
 crontab -l | { cat; echo "${CRONJOB}"; } | crontab -
fi

# Run build script if exists
if [ ! -z "$BUILD_SCRIPT" ]; then
    # Go to Webserver dir
    cd /var/www/html
    # Add execute permission if it is file
    if [ -f "$BUILD_SCRIPT" ]; then
    chmod +x $BUILD_SCRIPT
    fi
    nohup bash -c 'sleep 3 && su -c "$BUILD_SCRIPT" nginx' >/dev/null 2>&1 &
fi

# Customize Composer
if [ ! -z "$COMPOSER_MIRROR" ]; then
    su -c "composer config -g repos.packagist composer ${COMPOSER_MIRROR}" nginx
fi

# Start supervisord and services
/usr/bin/supervisord -n -c /etc/supervisord.conf
