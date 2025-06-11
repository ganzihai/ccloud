# 基于Ubuntu 20.04的集合性镜像
# 使用多阶段构建以减小最终镜像大小

# 第一阶段：基础构建环境
FROM ubuntu:22.04 AS builder

# 避免交互式前端
ENV DEBIAN_FRONTEND=noninteractive

# 更新apt源并安装基础构建工具
RUN apt-get update && apt-get install -y \
    build-essential \
    wget \
    curl \
    && rm -rf /var/lib/apt/lists/*

# 第二阶段：最终镜像
FROM ubuntu:22.04

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
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# 安装Go语言环境
RUN wget https://go.dev/dl/go1.24.4.linux-amd64.tar.gz \
    && tar -C /usr/local -xzf go1.24.4.linux-amd64.tar.gz \
    && rm go1.24.4.linux-amd64.tar.gz

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
RUN sed -i '/<Directory \/var\/www\/>/,/<\/Directory>/ s/AllowOverride None/AllowOverride All/' /etc/apache2/apache2.conf
# COPY 代码和配置文件
COPY maccms /var/www/html/maccms
COPY cron/maccms_cron /var/www/html/cron/maccms_cron
COPY supervisor/conf.d /var/www/html/supervisor/conf.d

# 权限设置
RUN chown -R mysql:mysql /var/www/html/mysql \
    && chmod -R 750 /var/www/html/mysql \
    && chown -R www-data:www-data /var/www/html/maccms \
    && chmod -R 755 /var/www/html/maccms \
    && chown -R root:root /var/www/html/supervisor \
    && chmod -R 755 /var/www/html/supervisor

# 将supervisor主配置文件放置正确位置，包含conf.d目录
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
[rpcinterface:supervisor]\n\
supervisor.rpcinterface_factory = supervisor.rpcinterface:make_main_rpcinterface\n\
\n\
[supervisorctl]\n\
serverurl=unix:///var/run/supervisor.sock\n\
\n\
[include]\n\
files=/var/www/html/supervisor/conf.d/*.conf\n' > /etc/supervisor/supervisord.conf

# 启动脚本中启动supervisord时用主配置文件路径
RUN sed -i 's#/etc/supervisor/conf.d/supervisord.conf#/etc/supervisor/supervisord.conf#' /start.sh

# 设置start.sh权限（你已有）
RUN chmod +x /start.sh

# 端口暴露保持不变
EXPOSE 80

CMD ["/start.sh"]
