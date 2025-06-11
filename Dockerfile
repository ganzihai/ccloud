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
    # 基础系统工具
    openssh-server \
    sudo \
    curl \
    wget \
    cron \
    nano \
    tar \
    gzip \
    unzip \
    sshpass \
    supervisor \
    tzdata \
    ca-certificates \
    software-properties-common \
    apt-transport-https \
    gnupg2 \
    lsb-release \
    net-tools \
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
    # Apache Web服务器
    apache2 \
    # PHP 7.4.33及常用扩展
    php7.4 \
    php7.4-fpm \
    php7.4-mysql \
    php7.4-curl \
    php7.4-gd \
    php7.4-mbstring \
    php7.4-xml \
    php7.4-zip \
    php7.4-json \
    php7.4-opcache \
    php7.4-readline \
    php7.4-common \
    php7.4-cli \
    libapache2-mod-php7.4 \
    && rm -rf /var/lib/apt/lists/*

# 启用Apache模块
RUN a2enmod rewrite && \
    a2enmod php7.4 && \
    a2enmod ssl && \
    a2enmod headers

# 配置Apache虚拟主机，根目录指向/var/www/html/maccms/
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

RUN echo "Listen 8008" >> /etc/apache2/ports.conf
RUN echo '<VirtualHost *:8008>' > /etc/apache2/sites-available/cloudsaver.conf && \
    echo '    ServerAdmin webmaster@localhost' >> /etc/apache2/sites-available/cloudsaver.conf && \
    echo '    DocumentRoot /var/www/html/cloudsaver/html' >> /etc/apache2/sites-available/cloudsaver.conf && \
    echo '    <Directory /var/www/html/cloudsaver/html>' >> /etc/apache2/sites-available/cloudsaver.conf && \
    echo '        Options -Indexes +FollowSymLinks' >> /etc/apache2/sites-available/cloudsaver.conf && \
    echo '        AllowOverride All' >> /etc/apache2/sites-available/cloudsaver.conf && \
    echo '        Require all granted' >> /etc/apache2/sites-available/cloudsaver.conf && \
    echo '    </Directory>' >> /etc/apache2/sites-available/cloudsaver.conf && \
    echo '    ErrorLog ${APACHE_LOG_DIR}/cloudsaver_error.log' >> /etc/apache2/sites-available/cloudsaver.conf && \
    echo '    CustomLog ${APACHE_LOG_DIR}/cloudsaver_access.log combined' >> /etc/apache2/sites-available/cloudsaver.conf && \
    echo '</VirtualHost>' >> /etc/apache2/sites-available/cloudsaver.conf && \
    a2ensite cloudsaver.conf
# ================================
# 第三阶段：数据库环境 (MySQL)
# ================================
FROM web-env as db-env

# 安装MySQL服务器
RUN apt-get update && \
    echo 'mysql-server mysql-server/root_password password temp_password' | debconf-set-selections && \
    echo 'mysql-server mysql-server/root_password_again password temp_password' | debconf-set-selections && \
    apt-get install -y mysql-server && \
    rm -rf /var/lib/apt/lists/*

# 配置MySQL数据目录到持久化路径
RUN mkdir -p /var/www/html/mysql && \
    chown mysql:mysql /var/www/html/mysql

# 修改MySQL配置文件，指定数据目录
RUN sed -i 's|datadir.*=.*|datadir = /var/www/html/mysql|g' /etc/mysql/mysql.conf.d/mysqld.cnf && \
    sed -i 's|bind-address.*=.*|bind-address = 0.0.0.0|g' /etc/mysql/mysql.conf.d/mysqld.cnf

# ================================
# 第四阶段：开发环境 (Python + Node.js + Go)
# ================================
FROM db-env as dev-env

# 安装Python 3.8及pip
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    python3.10 \
    python3.10-dev \
    python3.10-venv \
    python3-pip \
    && rm -rf /var/lib/apt/lists/*

# 创建Python符号链接
RUN ln -sf /usr/bin/python3.8 /usr/bin/python && \
    ln -sf /usr/bin/pip3 /usr/bin/pip

# 安装Node.js 22.x LTS
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && \
    apt-get install -y nodejs && \
    rm -rf /var/lib/apt/lists/*

# 安装Go语言环境 (最新稳定版)
RUN wget https://go.dev/dl/go1.24.4.linux-amd64.tar.gz && \
    tar -C /usr/local -xzf go1.24.4.linux-amd64.tar.gz && \
    rm go1.24.4.linux-amd64.tar.gz

# 设置Go环境变量
ENV PATH=$PATH:/usr/local/go/bin
ENV GOPATH=/var/www/html/go
ENV GOPROXY=https://goproxy.cn,direct

# ================================
# 第五阶段：最终镜像配置
# ================================
FROM dev-env as final

# 配置SSH服务
RUN mkdir /var/run/sshd && \
    # 允许root登录
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    # 禁用PAM
    sed -i 's@session\s*required\s*pam_loginuid.so@session optional pam_loginuid.so@g' /etc/pam.d/sshd && \
    # 设置SSH端口
    echo 'Port 22' >> /etc/ssh/sshd_config

# 创建必要的持久化目录结构
RUN mkdir -p /var/www/html/maccms && \
    mkdir -p /var/www/html/cron && \
    mkdir -p /var/www/html/supervisor/conf.d && \
    mkdir -p /var/www/html/mysql && \
    mkdir -p /var/www/html/go && \
    mkdir -p /var/www/html/python_venv && \
    mkdir -p /var/www/html/node_modules && \
    mkdir -p /var/www/html/ssl && \
    mkdir -p /var/log/supervisor

# 设置目录权限
RUN chown -R www-data:www-data /var/www/html && \
    chown mysql:mysql /var/www/html/mysql && \
    chmod 755 /var/www/html

# 配置Supervisor主配置文件
RUN echo '[unix_http_server]' > /etc/supervisor/supervisord.conf && \
    echo 'file=/var/run/supervisor.sock' >> /etc/supervisor/supervisord.conf && \
    echo 'chmod=0700' >> /etc/supervisor/supervisord.conf && \
    echo '' >> /etc/supervisor/supervisord.conf && \
    echo '[supervisord]' >> /etc/supervisor/supervisord.conf && \
    echo 'logfile=/var/log/supervisor/supervisord.log' >> /etc/supervisor/supervisord.conf && \
    echo 'pidfile=/var/run/supervisord.pid' >> /etc/supervisor/supervisord.conf && \
    echo 'childlogdir=/var/log/supervisor' >> /etc/supervisor/supervisord.conf && \
    echo 'nodaemon=true' >> /etc/supervisor/supervisord.conf && \
    echo 'user=root' >> /etc/supervisor/supervisord.conf && \
    echo '' >> /etc/supervisor/supervisord.conf && \
    echo '[rpcinterface:supervisor]' >> /etc/supervisor/supervisord.conf && \
    echo 'supervisor.rpcinterface_factory = supervisor.rpcinterface:make_main_rpcinterface' >> /etc/supervisor/supervisord.conf && \
    echo '' >> /etc/supervisor/supervisord.conf && \
    echo '[supervisorctl]' >> /etc/supervisor/supervisord.conf && \
    echo 'serverurl=unix:///var/run/supervisor.sock' >> /etc/supervisor/supervisord.conf && \
    echo '' >> /etc/supervisor/supervisord.conf && \
    echo '[include]' >> /etc/supervisor/supervisord.conf && \
    echo 'files = /var/www/html/supervisor/conf.d/*.conf' >> /etc/supervisor/supervisord.conf

# 创建启动脚本
RUN echo '#!/bin/bash' > /usr/local/bin/start.sh && \
    echo '# 容器启动脚本 - 遵循项目规范的初始化流程' >> /usr/local/bin/start.sh && \
    echo '' >> /usr/local/bin/start.sh && \
    echo '# 设置SSH root密码（通过环境变量SSH_PASSWORD传递，默认admin123）' >> /usr/local/bin/start.sh && \
    echo 'SSH_PASSWORD=${SSH_PASSWORD:-admin123}' >> /usr/local/bin/start.sh && \
    echo 'echo "root:$SSH_PASSWORD" | chpasswd' >> /usr/local/bin/start.sh && \
    echo 'echo "SSH root密码已设置"' >> /usr/local/bin/start.sh && \
    echo '' >> /usr/local/bin/start.sh && \
    echo '# 初始化MySQL数据目录（如果为空）' >> /usr/local/bin/start.sh && \
    echo 'if [ ! -d "/var/www/html/mysql/mysql" ]; then' >> /usr/local/bin/start.sh && \
    echo '    echo "初始化MySQL数据目录..."' >> /usr/local/bin/start.sh && \
    echo '    mysqld --initialize-insecure --user=mysql --datadir=/var/www/html/mysql' >> /usr/local/bin/start.sh && \
    echo '    echo "MySQL数据目录初始化完成"' >> /usr/local/bin/start.sh && \
    echo 'fi' >> /usr/local/bin/start.sh && \
    echo '' >> /usr/local/bin/start.sh && \
    echo '# 加载cron任务（从持久化目录）' >> /usr/local/bin/start.sh && \
    echo 'if [ -f "/var/www/html/cron/maccms_cron" ]; then' >> /usr/local/bin/start.sh && \
    echo '    echo "加载cron任务..."' >> /usr/local/bin/start.sh && \
    echo '    crontab /var/www/html/cron/maccms_cron' >> /usr/local/bin/start.sh && \
    echo '    echo "cron任务加载完成"' >> /usr/local/bin/start.sh && \
    echo 'else' >> /usr/local/bin/start.sh && \
    echo '    echo "警告: /var/www/html/cron/maccms_cron 文件不存在"' >> /usr/local/bin/start.sh && \
    echo 'fi' >> /usr/local/bin/start.sh && \
    echo '' >> /usr/local/bin/start.sh && \
    echo '# 启动cron任务监控脚本（后台运行）' >> /usr/local/bin/start.sh && \
    echo '/usr/local/bin/cron_monitor.sh &' >> /usr/local/bin/start.sh && \
    echo '' >> /usr/local/bin/start.sh && \
    echo '# 启动Supervisor（前台运行）' >> /usr/local/bin/start.sh && \
    echo 'echo "启动Supervisor服务管理器..."' >> /usr/local/bin/start.sh && \
    echo 'exec /usr/bin/supervisord -c /etc/supervisor/supervisord.conf' >> /usr/local/bin/start.sh && \
    chmod +x /usr/local/bin/start.sh

# 创建cron任务监控脚本（实时同步maccms_cron文件变化）
RUN echo '#!/bin/bash' > /usr/local/bin/cron_monitor.sh && \
    echo '# cron任务文件监控脚本 - 实时同步maccms_cron文件变化' >> /usr/local/bin/cron_monitor.sh && \
    echo '' >> /usr/local/bin/cron_monitor.sh && \
    echo 'CRON_FILE="/var/www/html/cron/maccms_cron"' >> /usr/local/bin/cron_monitor.sh && \
    echo 'LAST_MODIFIED=""' >> /usr/local/bin/cron_monitor.sh && \
    echo '' >> /usr/local/bin/cron_monitor.sh && \
    echo 'echo "启动cron任务监控..."' >> /usr/local/bin/cron_monitor.sh && \
    echo '' >> /usr/local/bin/cron_monitor.sh && \
    echo 'while true; do' >> /usr/local/bin/cron_monitor.sh && \
    echo '    if [ -f "$CRON_FILE" ]; then' >> /usr/local/bin/cron_monitor.sh && \
    echo '        CURRENT_MODIFIED=$(stat -c %Y "$CRON_FILE" 2>/dev/null)' >> /usr/local/bin/cron_monitor.sh && \
    echo '        if [ "$CURRENT_MODIFIED" != "$LAST_MODIFIED" ]; then' >> /usr/local/bin/cron_monitor.sh && \
    echo '            echo "检测到cron文件变化，重新加载..."' >> /usr/local/bin/cron_monitor.sh && \
    echo '            crontab "$CRON_FILE"' >> /usr/local/bin/cron_monitor.sh && \
    echo '            LAST_MODIFIED="$CURRENT_MODIFIED"' >> /usr/local/bin/cron_monitor.sh && \
    echo '            echo "cron任务已更新"' >> /usr/local/bin/cron_monitor.sh && \
    echo '        fi' >> /usr/local/bin/cron_monitor.sh && \
    echo '    fi' >> /usr/local/bin/cron_monitor.sh && \
    echo '    sleep 30  # 每30秒检查一次' >> /usr/local/bin/cron_monitor.sh && \
    echo 'done' >> /usr/local/bin/cron_monitor.sh && \
    chmod +x /usr/local/bin/cron_monitor.sh

# 设置工作目录
WORKDIR /var/www/html

# 暴露端口（仅80端口，其他服务通过frpc穿透）
EXPOSE 80

# 设置卷挂载点
VOLUME ["/var/www/html"]

# 容器启动命令
CMD ["/usr/local/bin/start.sh"]
