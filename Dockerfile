# Dockerfile (修正版)
# ------------------------------------------------------------------------------
# 阶段 1: 基础镜像选择
# 优化点: 使用 debian:bullseye-slim 代替 ubuntu:20.04，体积显著减小，且兼容 apt。
# ------------------------------------------------------------------------------
FROM debian:bullseye-slim

# 避免在构建过程中出现交互式提示
ARG DEBIAN_FRONTEND=noninteractive

# 设置语言环境和路径的环境变量
ENV NODE_VERSION=18.x
ENV GO_VERSION=1.21.5
ENV PATH="/usr/local/go/bin:${PATH}"

# ------------------------------------------------------------------------------
# 阶段 2: 核心依赖安装
# 优化点: 将所有 apt 安装合并到一个 RUN 指令中，以减少镜像层数。
# 优化点: 始终使用 --no-install-recommends 减少不必要的包安装。
# 优化点: 在指令的最后彻底清理 apt 缓存。
# ------------------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
    # 基础工具
    software-properties-common \
    ca-certificates \
    apt-transport-https \
    curl \
    wget \
    git \
    sudo \
    nano \
    tar \
    gzip \
    unzip \
    sshpass \
    # 用于定时任务文件监控
    inotify-tools \
    # 用于SSH服务
    openssh-server \
    # 用于服务管理
    supervisor \
    # 用于MySQL数据库 (Debian中包名为 default-mysql-server)
    default-mysql-server \
    # Python环境
    python3 \
    python3-pip \
    python3-venv \
    # PPA 和其他工具依赖
    gnupg \
    # 修正点: 添加 lsb-release 包，以确保 $(lsb_release -sc) 命令可以正常工作
    lsb-release \
    # 安装 PHP PPA 源 (ondrej/php)
    && curl -sSLo /usr/share/keyrings/deb.sury.org-php.gpg https://packages.sury.org/php/apt.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/deb.sury.org-php.gpg] https://packages.sury.org/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/php.list \
    # 安装 Node.js PPA 源
    && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /usr/share/keyrings/nodesource.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_VERSION} $(lsb_release -sc) main" > /etc/apt/sources.list.d/nodesource.list \
    # 再次更新以加载新的 PPA 源
    && apt-get update \
    # 安装 PHP, Node.js 及相关扩展
    && apt-get install -y --no-install-recommends \
    apache2 \
    libapache2-mod-php7.4 \
    php7.4 \
    php7.4-cli \
    php7.4-common \
    php7.4-mysql \
    php7.4-gd \
    php7.4-mbstring \
    php7.4-curl \
    php7.4-xml \
    php7.4-zip \
    php7.4-bcmath \
    nodejs \
    # 优化点: 在单个 RUN 指令的末尾执行清理操作
    && apt-get autoremove -y \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# ------------------------------------------------------------------------------
# 阶段 3: 语言与服务配置
# ------------------------------------------------------------------------------
# 配置 Apache
RUN a2enmod rewrite \
    && sed -i 's|/var/www/html|/var/www/html/maccms|g' /etc/apache2/sites-available/000-default.conf \
    && sed -i 's|AllowOverride None|AllowOverride All|g' /etc/apache2/apache2.conf

# 安装 Go 语言
# 优化点: 在同一层中下载、解压并删除临时文件
RUN wget "https://golang.org/dl/go${GO_VERSION}.linux-amd64.tar.gz" -O /tmp/go.tar.gz \
    && tar -C /usr/local -xzf /tmp/go.tar.gz \
    && rm /tmp/go.tar.gz

# 配置 SSH
RUN mkdir -p /var/run/sshd \
    && sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config

# 配置 MySQL
# Debian/MariaDB 的数据目录配置在 50-server.cnf 文件中
RUN sed -i 's|^datadir.*|datadir = /var/www/html/mysql|' /etc/mysql/mariadb.conf.d/50-server.cnf

# 配置 Supervisor
COPY supervisord.conf /etc/supervisor/supervisord.conf

# ------------------------------------------------------------------------------
# 阶段 4: 入口点与最终设置
# ------------------------------------------------------------------------------
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 80
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/usr/bin/supervisord", "-n", "-c", "/etc/supervisor/supervisord.conf"]
