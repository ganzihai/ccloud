# 多阶段构建 - 基于Ubuntu 22.04的集成开发环境镜像
# 严格遵循项目规范：单一镜像架构，单一卷持久化(/var/www/html/)

# ================================
# 第一阶段：基础环境构建
# ================================
FROM ubuntu:22.04 as base

# 设置环境变量，避免交互式安装
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Shanghai

# 更新系统并安装基础工具
RUN apt-get update && apt-get install -y \
    openssh-server sudo curl wget cron nano tar gzip unzip sshpass \
    supervisor tzdata ca-certificates software-properties-common \
    apt-transport-https gnupg2 lsb-release net-tools \
    && rm -rf /var/lib/apt/lists/*

# 设置时区
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# ================================
# 第二阶段：Web服务环境 (Apache + PHP 7.4.33)
# ================================
FROM base as web-env

# 添加PHP 7.4源并安装Apache和PHP
RUN add-apt-repository ppa:ondrej/php && \
    apt-get update && \
    apt-get install -y \
    apache2 php7.4 php7.4-fpm php7.4-mysql php7.4-curl php7.4-gd \
    php7.4-mbstring php7.4-xml php7.4-zip php7.4-json php7.4-opcache \
    php7.4-readline php7.4-common php7.4-cli libapache2-mod-php7.4 \
    && rm -rf /var/lib/apt/lists/*

# 启用Apache模块
RUN a2enmod rewrite php7.4 ssl headers proxy proxy_http

# 配置Apache虚拟主机 maccms
RUN echo '<VirtualHost *:80>' > /etc/apache2/sites-available/000-default.conf && \
    echo '    ServerAdmin webmaster@localhost' >> /etc/apache2/sites-available/000-default.conf && \
    echo '    DocumentRoot /var/www/html/maccms' >> /etc/apache2/sites-available/000-default.conf && \
    echo '    <Directory /var/www/html/maccms>' >> /etc/apache2/sites-available/000-default.conf && \
    echo '        Options Indexes FollowSymLinks' >> /etc/apache2/sites-available/000-default.conf && \
    echo '        AllowOverride All' >> /etc/apache2/sites-available/000-default.conf && \
    echo '        Require all granted' >> /etc/apache2/sites-available/000-default.conf && \
    echo '    </Directory>' >> /etc/apache2/sites-available/000-default.conf && \
    echo '    ErrorLog ${APACHE_LOG_DIR}/error.log' >> /etc/apache2/sites-available/000-default.conf && \
    echo '    CustomLog ${APACHE_LOG_DIR}/access.log combined' >> /etc/apache2/sites-available/000-default.conf && \
    echo '</VirtualHost>' >> /etc/apache2/sites-available/000-default.conf

# ================================
# 【最终修正】使用 <Location> 块来隔离反向代理
# ================================
RUN echo "Listen 8008" >> /etc/apache2/ports.conf && \
    echo '<VirtualHost *:8008>' > /etc/apache2/sites-available/cloudsaver.conf && \
    echo '    ServerAdmin webmaster@localhost' >> /etc/apache2/sites-available/cloudsaver.conf && \
    echo '    DocumentRoot /var/www/html/cloudsaver/html' >> /etc/apache2/sites-available/cloudsaver.conf && \
    echo '' >> /etc/apache2/sites-available/cloudsaver.conf && \
    echo '    <Location /api/>' >> /etc/apache2/sites-available/cloudsaver.conf && \
    echo '        ProxyPreserveHost On' >> /etc/apache2/sites-available/cloudsaver.conf && \
    echo '        ProxyPass http://127.0.0.1:8009/api/' >> /etc/apache2/sites-available/cloudsaver.conf && \
    echo '        ProxyPassReverse http://127.0.0.1:8009/api/' >> /etc/apache2/sites-available/cloudsaver.conf && \
    echo '    </Location>' >> /etc/apache2/sites-available/cloudsaver.conf && \
    echo '' >> /etc/apache2/sites-available/cloudsaver.conf && \
    echo '    <Directory /var/www/html/cloudsaver/html>' >> /etc/apache2/sites-available/cloudsaver.conf && \
    echo '        Options -Indexes +FollowSymLinks' >> /etc/apache2/sites-available/cloudsaver.conf && \
    echo '        AllowOverride All' >> /etc/apache2/sites-available/cloudsaver.conf && \
    echo '        Require all granted' >> /etc/apache2/sites-available/cloudsaver.conf && \
    echo '        RewriteEngine On' >> /etc/apache2/sites-available/cloudsaver.conf && \
    echo '        RewriteCond %{REQUEST_FILENAME} !-f' >> /etc/apache2/sites-available/cloudsaver.conf && \
    echo '        RewriteCond %{REQUEST_FILENAME} !-d' >> /etc/apache2/sites-available/cloudsaver.conf && \
    echo '        RewriteRule . /index.html [L]' >> /etc/apache2/sites-available/cloudsaver.conf && \
    echo '    </Directory>' >> /etc/apache2/sites-available/cloudsaver.conf && \
    echo '' >> /etc/apache2/sites-available/cloudsaver.conf && \
    echo '    ErrorLog ${APACHE_LOG_DIR}/cloudsaver_error.log' >> /etc/apache2/sites-available/cloudsaver.conf && \
    echo '    CustomLog ${APACHE_LOG_DIR}/cloudsaver_access.log combined' >> /etc/apache2/sites-available/cloudsaver.conf && \
    echo '</VirtualHost>' >> /etc/apache2/sites-available/cloudsaver.conf && \
    a2ensite cloudsaver.conf

# ================================
# 第三阶段：数据库环境 (MySQL)
# ================================
FROM web-env as db-env

RUN apt-get update && \
    echo 'mysql-server mysql-server/root_password password temp_password' | debconf-set-selections && \
    echo 'mysql-server mysql-server/root_password_again password temp_password' | debconf-set-selections && \
    apt-get install -y mysql-server && \
    rm -rf /var/lib/apt/lists/*

RUN mkdir -p /var/www/html/mysql && \
    chown mysql:mysql /var/www/html/mysql

RUN sed -i 's|datadir.*=.*|datadir = /var/www/html/mysql|g' /etc/mysql/mysql.conf.d/mysqld.cnf && \
    sed -i 's|bind-address.*=.*|bind-address = 0.0.0.0|g' /etc/mysql/mysql.conf.d/mysqld.cnf

# ================================
# 第四阶段：开发环境 (Python + Node.js + Go)
# ================================
FROM db-env as dev-env

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    python3.10 python3.10-dev python3.10-venv python3-pip \
    && rm -rf /var/lib/apt/lists/*

RUN ln -sf /usr/bin/python3.10 /usr/bin/python && \
    ln -sf /usr/bin/pip3 /usr/bin/pip

RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && \
    apt-get install -y nodejs && \
    rm -rf /var/lib/apt/lists/*

RUN wget https://go.dev/dl/go1.24.4.linux-amd64.tar.gz && \
    tar -C /usr/local -xzf go1.24.4.linux-amd64.tar.gz && \
    rm go1.24.4.linux-amd64.tar.gz

ENV PATH=$PATH:/usr/local/go/bin
ENV GOPATH=/var/www/html/go
ENV GOPROXY=https://goproxy.cn,direct

# ================================
# 第五阶段：最终镜像配置
# ================================
FROM dev-env as final

RUN mkdir /var/run/sshd && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's@session\s*required\s*pam_loginuid.so@session optional pam_loginuid.so@g' /etc/pam.d/sshd && \
    echo 'Port 22' >> /etc/ssh/sshd_config

RUN mkdir -p /var/www/html/{maccms,cron,supervisor/conf.d,mysql,go,python_venv,node_modules,ssl} && \
    mkdir -p /var/log/supervisor

RUN chown -R www-data:www-data /var/www/html && \
    chown mysql:mysql /var/www/html/mysql && \
    chmod 755 /var/www/html

RUN echo '[unix_http_server]' > /etc/supervisor/supervisord.conf && \
    echo 'file=/var/run/supervisor.sock' >> /etc/supervisor/supervisord.conf && \
    echo '[supervisord]' >> /etc/supervisor/supervisord.conf && \
    echo 'logfile=/var/log/supervisor/supervisord.log' >> /etc/supervisor/supervisord.conf && \
    echo 'pidfile=/var/run/supervisord.pid' >> /etc/supervisor/supervisord.conf && \
    echo 'nodaemon=true' >> /etc/supervisor/supervisord.conf && \
    echo 'user=root' >> /etc/supervisor/supervisord.conf && \
    echo '[rpcinterface:supervisor]' >> /etc/supervisor/supervisord.conf && \
    echo 'supervisor.rpcinterface_factory = supervisor.rpcinterface:make_main_rpcinterface' >> /etc/supervisor/supervisord.conf && \
    echo '[supervisorctl]' >> /etc/supervisor/supervisord.conf && \
    echo 'serverurl=unix:///var/run/supervisor.sock' >> /etc/supervisor/supervisord.conf && \
    echo '[include]' >> /etc/supervisor/supervisord.conf && \
    echo 'files = /var/www/html/supervisor/conf.d/*.conf' >> /etc/supervisor/supervisord.conf

RUN echo '#!/bin/bash' > /usr/local/bin/start.sh && \
    echo 'SSH_PASSWORD=${SSH_PASSWORD:-admin123}' >> /usr/local/bin/start.sh && \
    echo 'echo "root:$SSH_PASSWORD" | chpasswd' >> /usr/local/bin/start.sh && \
    echo 'if [ ! -d "/var/www/html/mysql/mysql" ]; then' >> /usr/local/bin/start.sh && \
    echo '    mysqld --initialize-insecure --user=mysql --datadir=/var/www/html/mysql' >> /usr/local/bin/start.sh && \
    echo 'fi' >> /usr/local/bin/start.sh && \
    echo 'if [ -f "/var/www/html/cron/maccms_cron" ]; then' >> /usr/local/bin/start.sh && \
    echo '    crontab /var/www/html/cron/maccms_cron' >> /usr/local/bin/start.sh && \
    echo 'fi' >> /usr/local/bin/start.sh && \
    echo '/usr/local/bin/cron_monitor.sh &' >> /usr/local/bin/start.sh && \
    echo 'exec /usr/bin/supervisord -c /etc/supervisor/supervisord.conf' >> /usr/local/bin/start.sh && \
    chmod +x /usr/local/bin/start.sh

RUN echo '#!/bin/bash' > /usr/local/bin/cron_monitor.sh && \
    echo 'CRON_FILE="/var/www/html/cron/maccms_cron"' >> /usr/local/bin/cron_monitor.sh && \
    echo 'LAST_MODIFIED=""' >> /usr/local/bin/cron_monitor.sh && \
    echo 'while true; do' >> /usr/local/bin/cron_monitor.sh && \
    echo '    if [ -f "$CRON_FILE" ]; then' >> /usr/local/bin/cron_monitor.sh && \
    echo '        CURRENT_MODIFIED=$(stat -c %Y "$CRON_FILE" 2>/dev/null)' >> /usr/local/bin/cron_monitor.sh && \
    echo '        if [ "$CURRENT_MODIFIED" != "$LAST_MODIFIED" ]; then' >> /usr/local/bin/cron_monitor.sh && \
    echo '            crontab "$CRON_FILE"' >> /usr/local/bin/cron_monitor.sh && \
    echo '            LAST_MODIFIED="$CURRENT_MODIFIED"' >> /usr/local/bin/cron_monitor.sh && \
    echo '        fi' >> /usr/local/bin/cron_monitor.sh && \
    echo '    fi' >> /usr/local/bin/cron_monitor.sh && \
    echo '    sleep 30' >> /usr/local/bin/cron_monitor.sh && \
    echo 'done' >> /usr/local/bin/cron_monitor.sh && \
    chmod +x /usr/local/bin/cron_monitor.sh

WORKDIR /var/www/html
EXPOSE 80
VOLUME ["/var/www/html"]
CMD ["/usr/local/bin/start.sh"]
