# 基于Ubuntu 20.04的集合性镜像
# 使用多阶段构建以减小最终镜像大小

# 第一阶段：基础构建环境
FROM ubuntu:20.04 AS builder

# 避免交互式前端
ENV DEBIAN_FRONTEND=noninteractive

# 更新apt源并安装基础构建工具
RUN apt-get update && apt-get install -y \
    build-essential \
    wget \
    curl \
    && rm -rf /var/lib/apt/lists/*

# 第二阶段：最终镜像
FROM ubuntu:20.04

# 避免交互式前端
ENV DEBIAN_FRONTEND=noninteractive

# 设置时区为亚洲/上海
RUN ln -fs /usr/share/zoneinfo/Asia/Shanghai /etc/localtime

# 更新apt源并安装基本工具
RUN apt-get update && apt-get install -y \
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
    net-tools \
    iputils-ping \
    && rm -rf /var/lib/apt/lists/*

# 安装Apache和PHP 7.4.33
RUN apt-get update && apt-get install -y \
    apache2 \
    software-properties-common \
    && add-apt-repository ppa:ondrej/php \
    && apt-get update \
    && apt-get install -y \
    php7.4 \
    php7.4-cli \
    php7.4-common \
    php7.4-curl \
    php7.4-gd \
    php7.4-json \
    php7.4-mbstring \
    php7.4-mysql \
    php7.4-xml \
    php7.4-zip \
    php7.4-fpm \
    libapache2-mod-php7.4 \
    && rm -rf /var/lib/apt/lists/*

# 安装MySQL
RUN apt-get update && apt-get install -y \
    mysql-server \
    && rm -rf /var/lib/apt/lists/*

# 配置MySQL数据目录
RUN mkdir -p /var/www/html/mysql
RUN chown -R mysql:mysql /var/www/html/mysql
# 创建MySQL配置文件
RUN mkdir -p /etc/mysql/mysql.conf.d/
RUN echo '[mysqld]\ndatadir=/var/www/html/mysql\nsocket=/var/run/mysqld/mysqld.sock\nuser=mysql\nsymbolic-links=0\n' > /etc/mysql/mysql.conf.d/mysqld.cnf
RUN mkdir -p /var/run/mysqld && chown mysql:mysql /var/run/mysqld

# 安装Node.js
RUN curl -fsSL https://deb.nodesource.com/setup_16.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# 安装Go语言环境
RUN wget https://golang.org/dl/go1.17.linux-amd64.tar.gz \
    && tar -C /usr/local -xzf go1.17.linux-amd64.tar.gz \
    && rm go1.17.linux-amd64.tar.gz

# 安装Python
RUN apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    python3-venv \
    && ln -s /usr/bin/python3 /usr/bin/python \
    && rm -rf /var/lib/apt/lists/*

# 配置环境变量
ENV PATH="/usr/local/go/bin:${PATH}"

# 配置SSH允许root登录
RUN mkdir -p /var/run/sshd
RUN echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config

# 创建必要的目录
RUN mkdir -p /var/www/html/maccms
RUN mkdir -p /var/www/html/cron
RUN mkdir -p /var/www/html/supervisor/conf.d

# 配置Apache虚拟主机
RUN echo '<VirtualHost *:80>\n\
    DocumentRoot /var/www/html/maccms\n\
    <Directory /var/www/html/maccms>\n\
        Options Indexes FollowSymLinks\n\
        AllowOverride All\n\
        Require all granted\n\
    </Directory>\n\
    ErrorLog ${APACHE_LOG_DIR}/error.log\n\
    CustomLog ${APACHE_LOG_DIR}/access.log combined\n\
</VirtualHost>' > /etc/apache2/sites-available/000-default.conf

# 启用Apache模块
RUN a2enmod rewrite

# 配置Supervisor
RUN echo '[supervisord]\n\
nodaemon=true\n\
logfile=/var/log/supervisor/supervisord.log\n\
pidfile=/var/run/supervisord.pid\n\
user=root\n\
\n\
[unix_http_server]\n\
file=/var/run/supervisor.sock\n\
chmod=0700\n\
\n\
[supervisorctl]\n\
serverurl=unix:///var/run/supervisor.sock\n\
\n\
[include]\n\
files=/var/www/html/supervisor/conf.d/*.conf\n\
\n\
[program:apache2]\n\
command=/usr/sbin/apache2ctl -D FOREGROUND\n\
autostart=true\n\
autorestart=true\n\
\n\
[program:mysql]\n\
command=/usr/sbin/mysqld --user=mysql --datadir=/var/www/html/mysql\n\
autostart=true\n\
autorestart=true\n\
\n\
[program:sshd]\n\
command=/usr/sbin/sshd -D\n\
autostart=true\n\
autorestart=true\n\
\n\
[program:cron]\n\
command=/usr/sbin/cron -f\n\
autostart=true\n\
autorestart=true' > /etc/supervisor/conf.d/supervisord.conf

# 创建启动脚本
RUN echo '#!/bin/bash\n\
\n\
# 设置root密码\n\
if [ -n "$SSH_PASSWORD" ]; then\n\
    echo "root:$SSH_PASSWORD" | chpasswd\n\
else\n\
    echo "root:admin123" | chpasswd\n\
fi\n\
\n\
# 初始化MySQL数据目录（如果为空）\n\
if [ ! "$(ls -A /var/www/html/mysql)" ]; then\n\
    mkdir -p /var/www/html/mysql\n\
    chown -R mysql:mysql /var/www/html/mysql\n\
    mysqld --initialize-insecure --datadir=/var/www/html/mysql --user=mysql\n\
    chown -R mysql:mysql /var/www/html/mysql\n\
fi\n\
\n\
# 加载cron任务\n\
if [ -f /var/www/html/cron/maccms_cron ]; then\n\
    crontab /var/www/html/cron/maccms_cron\n\
fi\n\
\n\
# 启动supervisor\n\
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf' > /start.sh

# 设置执行权限
RUN chmod +x /start.sh

# 暴露端口
EXPOSE 22 80 3306

# 设置启动命令
CMD ["/start.sh"] 
