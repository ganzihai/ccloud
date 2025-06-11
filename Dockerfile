# 多阶段构建 - 基于 Ubuntu 20.04 的集成镜像
# 严格遵循项目规范：单一镜像架构，单一卷持久化

# ================================
# 阶段 1: 基础环境构建
# ================================
FROM ubuntu:20.04 as base

# 设置环境变量避免交互式安装
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
    gnupg \
    lsb-release \
    && rm -rf /var/lib/apt/lists/*

# 设置时区
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# ================================
# 阶段 2: 开发环境构建
# ================================
FROM base as dev-env

# 安装 Python 3.8 及相关工具
RUN apt-get update && apt-get install -y \
    python3.8 \
    python3.8-dev \
    python3-pip \
    python3.8-venv \
    && rm -rf /var/lib/apt/lists/*

# 创建 Python 符号链接
RUN ln -sf /usr/bin/python3.8 /usr/bin/python && \
    ln -sf /usr/bin/python3.8 /usr/bin/python3

# 安装 Node.js 16.x LTS
RUN curl -fsSL https://deb.nodesource.com/setup_16.x | bash - && \
    apt-get install -y nodejs && \
    rm -rf /var/lib/apt/lists/*

# 安装 Go 1.19
RUN wget https://go.dev/dl/go1.19.linux-amd64.tar.gz && \
    tar -C /usr/local -xzf go1.19.linux-amd64.tar.gz && \
    rm go1.19.linux-amd64.tar.gz

# 设置 Go 环境变量
ENV PATH=$PATH:/usr/local/go/bin
ENV GOPATH=/var/www/html/go
ENV GOPROXY=https://goproxy.cn,direct

# ================================
# 阶段 3: Web 服务环境构建
# ================================
FROM dev-env as web-env

# 安装 Apache2
RUN apt-get update && apt-get install -y \
    apache2 \
    && rm -rf /var/lib/apt/lists/*

# 添加 PHP 7.4 仓库并安装 PHP 7.4.33
RUN add-apt-repository ppa:ondrej/php && \
    apt-get update && apt-get install -y \
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

# 启用 Apache 模块
RUN a2enmod rewrite php7.4 ssl headers

# 配置 Apache 虚拟主机指向 maccms 目录
RUN echo '<VirtualHost *:80>' > /etc/apache2/sites-available/maccms.conf && \
    echo '    ServerName localhost' >> /etc/apache2/sites-available/maccms.conf && \
    echo '    DocumentRoot /var/www/html/maccms' >> /etc/apache2/sites-available/maccms.conf && \
    echo '    <Directory /var/www/html/maccms>' >> /etc/apache2/sites-available/maccms.conf && \
    echo '        AllowOverride All' >> /etc/apache2/sites-available/maccms.conf && \
    echo '        Require all granted' >> /etc/apache2/sites-available/maccms.conf && \
    echo '    </Directory>' >> /etc/apache2/sites-available/maccms.conf && \
    echo '    ErrorLog ${APACHE_LOG_DIR}/maccms_error.log' >> /etc/apache2/sites-available/maccms.conf && \
    echo '    CustomLog ${APACHE_LOG_DIR}/maccms_access.log combined' >> /etc/apache2/sites-available/maccms.conf && \
    echo '</VirtualHost>' >> /etc/apache2/sites-available/maccms.conf

# 启用 maccms 站点，禁用默认站点
RUN a2ensite maccms.conf && a2dissite 000-default.conf

# ================================
# 阶段 4: 数据库环境构建
# ================================
FROM web-env as db-env

# 安装 MySQL 8.0
RUN apt-get update && \
    echo 'mysql-server mysql-server/root_password password temp_password' | debconf-set-selections && \
    echo 'mysql-server mysql-server/root_password_again password temp_password' | debconf-set-selections && \
    apt-get install -y mysql-server && \
    rm -rf /var/lib/apt/lists/*

# 创建 MySQL 数据目录的符号链接脚本
RUN echo '#!/bin/bash' > /usr/local/bin/setup-mysql.sh && \
    echo '# 确保持久化目录存在' >> /usr/local/bin/setup-mysql.sh && \
    echo 'mkdir -p /var/www/html/mysql' >> /usr/local/bin/setup-mysql.sh && \
    echo '# 如果持久化目录为空，初始化数据库' >> /usr/local/bin/setup-mysql.sh && \
    echo 'if [ ! -d "/var/www/html/mysql/mysql" ]; then' >> /usr/local/bin/setup-mysql.sh && \
    echo '    echo "初始化 MySQL 数据目录..."' >> /usr/local/bin/setup-mysql.sh && \
    echo '    cp -r /var/lib/mysql/* /var/www/html/mysql/' >> /usr/local/bin/setup-mysql.sh && \
    echo '    chown -R mysql:mysql /var/www/html/mysql' >> /usr/local/bin/setup-mysql.sh && \
    echo 'fi' >> /usr/local/bin/setup-mysql.sh && \
    echo '# 创建符号链接' >> /usr/local/bin/setup-mysql.sh && \
    echo 'rm -rf /var/lib/mysql' >> /usr/local/bin/setup-mysql.sh && \
    echo 'ln -sf /var/www/html/mysql /var/lib/mysql' >> /usr/local/bin/setup-mysql.sh && \
    echo 'chown -R mysql:mysql /var/lib/mysql' >> /usr/local/bin/setup-mysql.sh && \
    chmod +x /usr/local/bin/setup-mysql.sh

# ================================
# 阶段 5: 最终镜像构建
# ================================
FROM db-env as final

# 配置 SSH 服务
RUN mkdir /var/run/sshd && \
    # 允许 root 登录
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    # 禁用 PAM
    sed -i 's@session\s*required\s*pam_loginuid.so@session optional pam_loginuid.so@g' /etc/pam.d/sshd

# 创建 SSH 密码设置脚本
RUN echo '#!/bin/bash' > /usr/local/bin/setup-ssh.sh && \
    echo '# 设置 root 密码' >> /usr/local/bin/setup-ssh.sh && \
    echo 'SSH_PASS=${SSH_PASSWORD:-admin123}' >> /usr/local/bin/setup-ssh.sh && \
    echo 'echo "root:$SSH_PASS" | chpasswd' >> /usr/local/bin/setup-ssh.sh && \
    echo 'echo "SSH root 密码已设置"' >> /usr/local/bin/setup-ssh.sh && \
    chmod +x /usr/local/bin/setup-ssh.sh

# 创建 cron 任务同步脚本
RUN echo '#!/bin/bash' > /usr/local/bin/sync-cron.sh && \
    echo '# 同步 cron 任务' >> /usr/local/bin/sync-cron.sh && \
    echo 'CRON_FILE="/var/www/html/cron/maccms_cron"' >> /usr/local/bin/sync-cron.sh && \
    echo 'if [ -f "$CRON_FILE" ]; then' >> /usr/local/bin/sync-cron.sh && \
    echo '    echo "加载 cron 任务..."' >> /usr/local/bin/sync-cron.sh && \
    echo '    crontab "$CRON_FILE"' >> /usr/local/bin/sync-cron.sh && \
    echo '    echo "Cron 任务已加载"' >> /usr/local/bin/sync-cron.sh && \
    echo 'else' >> /usr/local/bin/sync-cron.sh && \
    echo '    echo "警告: $CRON_FILE 不存在"' >> /usr/local/bin/sync-cron.sh && \
    echo 'fi' >> /usr/local/bin/sync-cron.sh && \
    chmod +x /usr/local/bin/sync-cron.sh

# 创建 cron 监控脚本（监控文件变化并自动同步）
RUN echo '#!/bin/bash' > /usr/local/bin/monitor-cron.sh && \
    echo '# 监控 cron 文件变化' >> /usr/local/bin/monitor-cron.sh && \
    echo 'CRON_FILE="/var/www/html/cron/maccms_cron"' >> /usr/local/bin/monitor-cron.sh && \
    echo 'LAST_MODIFIED=""' >> /usr/local/bin/monitor-cron.sh && \
    echo 'while true; do' >> /usr/local/bin/monitor-cron.sh && \
    echo '    if [ -f "$CRON_FILE" ]; then' >> /usr/local/bin/monitor-cron.sh && \
    echo '        CURRENT_MODIFIED=$(stat -c %Y "$CRON_FILE" 2>/dev/null)' >> /usr/local/bin/monitor-cron.sh && \
    echo '        if [ "$CURRENT_MODIFIED" != "$LAST_MODIFIED" ]; then' >> /usr/local/bin/monitor-cron.sh && \
    echo '            echo "检测到 cron 文件变化，重新加载..."' >> /usr/local/bin/monitor-cron.sh && \
    echo '            crontab "$CRON_FILE"' >> /usr/local/bin/monitor-cron.sh && \
    echo '            LAST_MODIFIED="$CURRENT_MODIFIED"' >> /usr/local/bin/monitor-cron.sh && \
    echo '            echo "Cron 任务已更新"' >> /usr/local/bin/monitor-cron.sh && \
    echo '        fi' >> /usr/local/bin/monitor-cron.sh && \
    echo '    fi' >> /usr/local/bin/monitor-cron.sh && \
    echo '    sleep 10' >> /usr/local/bin/monitor-cron.sh && \
    echo 'done' >> /usr/local/bin/monitor-cron.sh && \
    chmod +x /usr/local/bin/monitor-cron.sh

# 配置 Supervisor 主配置文件
RUN echo '[unix_http_server]' > /etc/supervisor/supervisord.conf && \
    echo 'file=/var/run/supervisor.sock' >> /etc/supervisor/supervisord.conf && \
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

# 创建默认的 Supervisor 服务配置文件
RUN mkdir -p /etc/supervisor/conf.d

# Apache 服务配置
RUN echo '[program:apache2]' > /etc/supervisor/conf.d/apache2.conf && \
    echo 'command=/bin/bash -c "sleep 30 && /usr/sbin/apache2ctl -D FOREGROUND"' >> /etc/supervisor/conf.d/apache2.conf && \
    echo 'autostart=true' >> /etc/supervisor/conf.d/apache2.conf && \
    echo 'autorestart=true' >> /etc/supervisor/conf.d/apache2.conf && \
    echo 'priority=10' >> /etc/supervisor/conf.d/apache2.conf && \
    echo 'stdout_logfile=/var/log/supervisor/apache2.log' >> /etc/supervisor/conf.d/apache2.conf && \
    echo 'stderr_logfile=/var/log/supervisor/apache2_error.log' >> /etc/supervisor/conf.d/apache2.conf

# MySQL 服务配置
RUN echo '[program:mysql]' > /etc/supervisor/conf.d/mysql.conf && \
    echo 'command=/bin/bash -c "sleep 10 && /usr/local/bin/setup-mysql.sh && /usr/bin/mysqld_safe"' >> /etc/supervisor/conf.d/mysql.conf && \
    echo 'autostart=true' >> /etc/supervisor/conf.d/mysql.conf && \
    echo 'autorestart=true' >> /etc/supervisor/conf.d/mysql.conf && \
    echo 'priority=5' >> /etc/supervisor/conf.d/mysql.conf && \
    echo 'stdout_logfile=/var/log/supervisor/mysql.log' >> /etc/supervisor/conf.d/mysql.conf && \
    echo 'stderr_logfile=/var/log/supervisor/mysql_error.log' >> /etc/supervisor/conf.d/mysql.conf

# SSH 服务配置
RUN echo '[program:sshd]' > /etc/supervisor/conf.d/sshd.conf && \
    echo 'command=/bin/bash -c "sleep 5 && /usr/local/bin/setup-ssh.sh && /usr/sbin/sshd -D"' >> /etc/supervisor/conf.d/sshd.conf && \
    echo 'autostart=true' >> /etc/supervisor/conf.d/sshd.conf && \
    echo 'autorestart=true' >> /etc/supervisor/conf.d/sshd.conf && \
    echo 'priority=15' >> /etc/supervisor/conf.d/sshd.conf && \
    echo 'stdout_logfile=/var/log/supervisor/sshd.log' >> /etc/supervisor/conf.d/sshd.conf && \
    echo 'stderr_logfile=/var/log/supervisor/sshd_error.log' >> /etc/supervisor/conf.d/sshd.conf

# Cron 服务配置
RUN echo '[program:cron]' > /etc/supervisor/conf.d/cron.conf && \
    echo 'command=/bin/bash -c "sleep 20 && /usr/local/bin/sync-cron.sh && /usr/sbin/cron -f"' >> /etc/supervisor/conf.d/cron.conf && \
    echo 'autostart=true' >> /etc/supervisor/conf.d/cron.conf && \
    echo 'autorestart=true' >> /etc/supervisor/conf.d/cron.conf && \
    echo 'priority=25' >> /etc/supervisor/conf.d/cron.conf && \
    echo 'stdout_logfile=/var/log/supervisor/cron.log' >> /etc/supervisor/conf.d/cron.conf && \
    echo 'stderr_logfile=/var/log/supervisor/cron_error.log' >> /etc/supervisor/conf.d/cron.conf

# Cron 监控服务配置
RUN echo '[program:cron-monitor]' > /etc/supervisor/conf.d/cron-monitor.conf && \
    echo 'command=/bin/bash -c "sleep 35 && /usr/local/bin/monitor-cron.sh"' >> /etc/supervisor/conf.d/cron-monitor.conf && \
    echo 'autostart=true' >> /etc/supervisor/conf.d/cron-monitor.conf && \
    echo 'autorestart=true' >> /etc/supervisor/conf.d/cron-monitor.conf && \
    echo 'priority=30' >> /etc/supervisor/conf.d/cron-monitor.conf && \
    echo 'stdout_logfile=/var/log/supervisor/cron-monitor.log' >> /etc/supervisor/conf.d/cron-monitor.conf && \
    echo 'stderr_logfile=/var/log/supervisor/cron-monitor_error.log' >> /etc/supervisor/conf.d/cron-monitor.conf

# 创建启动脚本
RUN echo '#!/bin/bash' > /usr/local/bin/start-services.sh && \
    echo '# 确保必要的目录存在' >> /usr/local/bin/start-services.sh && \
    echo 'mkdir -p /var/www/html/supervisor/conf.d' >> /usr/local/bin/start-services.sh && \
    echo 'mkdir -p /var/www/html/cron' >> /usr/local/bin/start-services.sh && \
    echo 'mkdir -p /var/www/html/mysql' >> /usr/local/bin/start-services.sh && \
    echo 'mkdir -p /var/www/html/maccms' >> /usr/local/bin/start-services.sh && \
    echo 'mkdir -p /var/log/supervisor' >> /usr/local/bin/start-services.sh && \
    echo '' >> /usr/local/bin/start-services.sh && \
    echo '# 设置权限' >> /usr/local/bin/start-services.sh && \
    echo 'chown -R www-data:www-data /var/www/html' >> /usr/local/bin/start-services.sh && \
    echo 'chmod -R 755 /var/www/html' >> /usr/local/bin/start-services.sh && \
    echo '' >> /usr/local/bin/start-services.sh && \
    echo '# 启动 Supervisor' >> /usr/local/bin/start-services.sh && \
    echo 'exec /usr/bin/supervisord -c /etc/supervisor/supervisord.conf' >> /usr/local/bin/start-services.sh && \
    chmod +x /usr/local/bin/start-services.sh

# 创建必要的目录
RUN mkdir -p /var/www/html && \
    mkdir -p /var/log/supervisor && \
    chown -R www-data:www-data /var/www/html

# 暴露端口
EXPOSE 80

# 设置工作目录
WORKDIR /var/www/html

# 启动命令
CMD ["/usr/local/bin/start-services.sh"]
