# ================================
# 多阶段构建 - 基于Ubuntu 22.04的集成开发环境镜像
# 严格遵循项目规范：单一镜像架构，单一卷持久化(/var/www/html/)
# ================================

# 定义可配置的软件版本
ARG PHP_VERSION=7.4
ARG NODE_VERSION=22.x
ARG GO_VERSION=1.24.4

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
# 第二阶段：Web服务环境 (Apache + PHP)
# ================================
FROM base as web-env

ARG PHP_VERSION

# 添加PPA并安装Apache和PHP
RUN add-apt-repository ppa:ondrej/php && apt-get update && apt-get install -y \
    apache2 \
    php${PHP_VERSION} php${PHP_VERSION}-fpm php${PHP_VERSION}-mysql php${PHP_VERSION}-curl \
    php${PHP_VERSION}-gd php${PHP_VERSION}-mbstring php${PHP_VERSION}-xml php${PHP_VERSION}-zip \
    php${PHP_VERSION}-json php${PHP_VERSION}-opcache php${PHP_VERSION}-readline \
    php${PHP_VERSION}-common php${PHP_VERSION}-cli libapache2-mod-php${PHP_VERSION} \
    && rm -rf /var/lib/apt/lists/*

# 拷贝Apache配置文件
COPY docker_config/000-default.conf /etc/apache2/sites-available/000-default.conf
COPY docker_config/cloudsaver.conf /etc/apache2/sites-available/cloudsaver.conf

# 监听新端口并启用模块和站点
RUN echo "Listen 8008" >> /etc/apache2/ports.conf && \
    a2enmod rewrite php${PHP_VERSION} ssl headers proxy proxy_http && \
    a2ensite cloudsaver.conf

# ================================
# 第三阶段：数据库环境 (MySQL)
# ================================
FROM web-env as db-env

# 安装MySQL服务器 (使用debconf预设密码)
RUN echo 'mysql-server mysql-server/root_password password temp_password' | debconf-set-selections && \
    echo 'mysql-server mysql-server/root_password_again password temp_password' | debconf-set-selections && \
    apt-get update && apt-get install -y mysql-server && rm -rf /var/lib/apt/lists/*

# 修改MySQL配置文件，指定数据目录并允许远程连接
RUN sed -i 's|datadir.*=.*|datadir = /var/www/html/mysql|g' /etc/mysql/mysql.conf.d/mysqld.cnf && \
    sed -i 's|bind-address.*=.*|bind-address = 0.0.0.0|g' /etc/mysql/mysql.conf.d/mysqld.cnf

# ================================
# 第四阶段：开发环境 (Python + Node.js + Go)
# ================================
FROM db-env as dev-env

ARG NODE_VERSION
ARG GO_VERSION

# 安装Python, Node.js
RUN apt-get update && \
    apt-get install -y --no-install-recommends python3.10 python3.10-dev python3.10-venv python3-pip && \
    curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION} | bash - && \
    apt-get install -y nodejs && \
    rm -rf /var/lib/apt/lists/*

# 安装Go
RUN wget https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz && \
    tar -C /usr/local -xzf go${GO_VERSION}.linux-amd64.tar.gz && \
    rm go${GO_VERSION}.linux-amd64.tar.gz

# 创建Python符号链接 (修正BUG)
RUN ln -sf /usr/bin/python3.10 /usr/bin/python && \
    ln -sf /usr/bin/pip3 /usr/bin/pip

# 设置Go环境变量
ENV PATH=$PATH:/usr/local/go/bin
ENV GOPATH=/var/www/html/go
ENV GOPROXY=https://goproxy.cn,direct

# ================================
# 第五阶段：最终镜像配置
# ================================
FROM dev-env as final

# 拷贝配置文件和启动脚本
COPY docker_config/supervisord.conf /etc/supervisor/supervisord.conf
COPY docker_config/start.sh /usr/local/bin/start.sh
COPY docker_config/cron_monitor.sh /usr/local/bin/cron_monitor.sh

# 配置SSH服务
RUN mkdir /var/run/sshd && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's@session\s*required\s*pam_loginuid.so@session optional pam_loginuid.so@g' /etc/pam.d/sshd && \
    echo 'Port 22' >> /etc/ssh/sshd_config

# 创建必要的持久化目录结构并设置权限
RUN mkdir -p /var/www/html/{maccms,cron,supervisor/conf.d,mysql,go,python_venv,node_modules,ssl} \
    && mkdir -p /var/log/supervisor \
    && chown -R www-data:www-data /var/www/html \
    && chown mysql:mysql /var/www/html/mysql \
    && chmod 755 /var/www/html \
    && chmod +x /usr/local/bin/start.sh /usr/local/bin/cron_monitor.sh

# 设置工作目录
WORKDIR /var/www/html

# 暴露端口
EXPOSE 80 8008

# 设置卷挂载点
VOLUME ["/var/www/html"]

# 容器启动命令
CMD ["/usr/local/bin/start.sh"]
