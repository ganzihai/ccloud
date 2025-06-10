# 第一阶段：从CloudSaver镜像中提取文件
FROM jiangrui1994/cloudsaver:latest AS cloudsaver

# 第二阶段：构建主镜像
FROM ubuntu:22.04

# 设置环境变量
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Shanghai
ENV PHP_VERSION=7.4
ENV NODE_VERSION=18
ENV GO_VERSION=1.24.4

# 更新系统并安装基础包
RUN apt-get update && apt-get install -y \
    git \
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
    python3 \
    python3-pip \
    software-properties-common \
    ca-certificates \
    gnupg \
    lsb-release \
    supervisor \
    nginx \
    && rm -rf /var/lib/apt/lists/*

# 安装PHP 7.4和相关扩展
RUN add-apt-repository ppa:ondrej/php && \
    apt-get update && \
    apt-get install -y \
    php7.4 \
    php7.4-fpm \
    php7.4-cli \
    php7.4-common \
    php7.4-mysql \
    php7.4-zip \
    php7.4-gd \
    php7.4-mbstring \
    php7.4-curl \
    php7.4-xml \
    php7.4-bcmath \
    php7.4-json \
    php7.4-intl \
    php7.4-soap \
    php7.4-fileinfo \
    php7.4-redis \
    php7.4-opcache \
    && rm -rf /var/lib/apt/lists/*

# 安装Composer
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

# 安装MySQL
RUN apt-get update && \
    apt-get install -y mysql-server mysql-client && \
    rm -rf /var/lib/apt/lists/*

# 安装Node.js
RUN curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash - && \
    apt-get install -y nodejs

# 安装Go语言
RUN wget https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz && \
    tar -C /usr/local -xzf go${GO_VERSION}.linux-amd64.tar.gz && \
    rm go${GO_VERSION}.linux-amd64.tar.gz

# 设置Go环境变量
ENV PATH=$PATH:/usr/local/go/bin
ENV GOPATH=/var/www/html/go
ENV GOPROXY=https://goproxy.cn,direct

# 从CloudSaver镜像复制应用文件
COPY --from=cloudsaver /app /var/www/html/cloudsaver

# 创建必要的目录结构
RUN mkdir -p /var/www/html/maccms \
    /var/www/html/supervisor/conf.d \
    /var/www/html/logs \
    /var/www/html/config \
    /var/www/html/cron \
    /var/www/html/frpc \
    /var/www/html/go \
    /var/run/sshd \
    /var/log/supervisor

# 配置SSH
RUN sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    sed -i 's/#Port 22/Port 22/' /etc/ssh/sshd_config && \
    echo 'root:${SSH_PASSWORD:-admin123}' | chpasswd

# 配置MySQL
RUN service mysql start && \
    mysql -e "CREATE DATABASE IF NOT EXISTS maccms DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" && \
    mysql -e "CREATE USER IF NOT EXISTS 'maccms'@'localhost' IDENTIFIED BY 'maccms123';" && \
    mysql -e "GRANT ALL PRIVILEGES ON maccms.* TO 'maccms'@'localhost';" && \
    mysql -e "FLUSH PRIVILEGES;"

# 配置PHP-FPM
RUN sed -i 's/listen = \/run\/php\/php7.4-fpm.sock/listen = 127.0.0.1:9000/' /etc/php/7.4/fpm/pool.d/www.conf

# 配置Nginx
COPY <<EOF /etc/nginx/sites-available/default
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    
    root /var/www/html/maccms;
    index index.php index.html index.htm;
    
    server_name _;
    
    # 直接访问maccms项目
    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }
    
    # PHP处理
    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass 127.0.0.1:9000;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    }
    
    location ~ /\.ht {
        deny all;
    }
}
EOF

# 配置supervisor主配置文件
COPY <<EOF /etc/supervisor/supervisord.conf
[unix_http_server]
file=/var/run/supervisor.sock
chmod=0700

[supervisord]
nodaemon=true
logfile=/var/log/supervisor/supervisord.log
pidfile=/var/run/supervisord.pid
childlogdir=/var/log/supervisor

[rpcinterface:supervisor]
supervisor.rpcinterface_factory = supervisor.rpcinterface:make_main_rpcinterface

[supervisorctl]
serverurl=unix:///var/run/supervisor.sock

[include]
files = /etc/supervisor/conf.d/*.conf /var/www/html/supervisor/conf.d/*.conf
EOF

# 创建基础supervisor配置
COPY <<EOF /etc/supervisor/conf.d/base-services.conf
[program:mysql]
command=/usr/bin/mysqld_safe --datadir=/var/lib/mysql --socket=/var/run/mysqld/mysqld.sock --pid-file=/var/run/mysqld/mysqld.pid --basedir=/usr --user=mysql
autostart=true
autorestart=true
priority=10
stdout_logfile=/var/log/supervisor/mysql.log
stderr_logfile=/var/log/supervisor/mysql_error.log

[program:php-fpm]
command=/usr/sbin/php-fpm7.4 --nodaemonize --fpm-config /etc/php/7.4/fpm/php-fpm.conf
autostart=true
autorestart=true
priority=15
stdout_logfile=/var/log/supervisor/php-fpm.log
stderr_logfile=/var/log/supervisor/php-fpm_error.log

[program:nginx]
command=/usr/sbin/nginx -g "daemon off;"
autostart=true
autorestart=true
priority=20
stdout_logfile=/var/log/supervisor/nginx.log
stderr_logfile=/var/log/supervisor/nginx_error.log

[program:sshd]
command=/usr/sbin/sshd -D
autostart=true
autorestart=true
priority=25
stdout_logfile=/var/log/supervisor/sshd.log
stderr_logfile=/var/log/supervisor/sshd_error.log

[program:cron]
command=/usr/sbin/cron -f
autostart=true
autorestart=true
priority=30
stdout_logfile=/var/log/supervisor/cron.log
stderr_logfile=/var/log/supervisor/cron_error.log

[program:cloudsaver]
command=/bin/bash -c "sleep 30 && cd /var/www/html/cloudsaver && JWT_SECRET=a8f5f167f44f4964e6c998dee827110c node dist-final/app.js"
autostart=true
autorestart=true
priority=35
stdout_logfile=/var/log/supervisor/cloudsaver.log
stderr_logfile=/var/log/supervisor/cloudsaver_error.log
environment=JWT_SECRET="a8f5f167f44f4964e6c998dee827110c"
EOF

# 创建启动脚本
COPY <<EOF /usr/local/bin/start.sh
#!/bin/bash

# 设置SSH密码
if [ ! -z "\$SSH_PASSWORD" ]; then
    echo "root:\$SSH_PASSWORD" | chpasswd
fi

# 确保MySQL数据目录权限正确
chown -R mysql:mysql /var/lib/mysql
chmod 755 /var/lib/mysql

# 确保挂载目录权限正确
chown -R www-data:www-data /var/www/html
chmod -R 755 /var/www/html

# 启动supervisor
exec /usr/bin/supervisord -c /etc/supervisor/supervisord.conf
EOF

RUN chmod +x /usr/local/bin/start.sh

# 添加frpc服务配置
COPY <<EOF /etc/supervisor/conf.d/frpc.conf
[program:frpc]
command=/bin/bash -c "sleep 30 && /var/www/html/frpc/frpc -c /var/www/html/frpc/frpc.ini"
autostart=true
autorestart=true
priority=40
stdout_logfile=/var/log/supervisor/frpc.log
stderr_logfile=/var/log/supervisor/frpc_error.log
user=root
EOF

# 设置工作目录
WORKDIR /var/www/html

# 暴露端口
EXPOSE 80

# 启动命令
CMD ["/usr/local/bin/start.sh"]
