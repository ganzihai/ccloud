# 使用官方 Ubuntu 20.04 作为基础镜像
FROM ubuntu:20.04

# 作者信息
LABEL maintainer="Ganzi>"

# 设置环境变量，避免安装过程中的交互式提示
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Shanghai
# --------------------------------------------------------------------
# 第一阶段：安装系统基础工具和依赖
# --------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
    # 核心工具
    sudo curl wget nano tar gzip unzip sshpass ca-certificates \
    # 添加 PPA 和其他仓库所需的工具
    software-properties-common \
    # Supervisor 和 Cron
    supervisor cron \
    # SSH 服务
    openssh-server \
    # Cron 文件监控工具
    inotify-tools \
    # 权限管理
    acl \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# --------------------------------------------------------------------
# 第二阶段：安装多语言环境 (Python, Node.js, Go)
# --------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
    # 安装 Python 3 和 pip
    python3 python3-pip \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# 安装 Node.js (使用 NodeSource 官方推荐方式安装 LTS 版本)
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# 安装 Go 语言 (使用官方二进制包)
ENV GO_VERSION=1.24.4
RUN wget https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz -O /tmp/go.tar.gz \
    && tar -C /usr/local -xzf /tmp/go.tar.gz \
    && rm /tmp/go.tar.gz
# 将 Go 的路径添加到全局 PATH
ENV PATH=$PATH:/usr/local/go/bin

# --------------------------------------------------------------------
# 第三阶段：安装并配置 Apache + PHP 7.4.33
# --------------------------------------------------------------------
RUN add-apt-repository ppa:ondrej/php -y \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
    # Apache 服务器
    apache2 \
    # 指定 PHP 版本及常用扩展 (Maccms 常用)
    php7.4 libapache2-mod-php7.4 \
    php7.4-cli php7.4-common php7.4-mysql php7.4-gd php7.4-mbstring \
    php7.4-curl php7.4-xml php7.4-zip php7.4-opcache \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# 配置 Apache
# 创建新的站点配置文件，将根目录指向持久化卷中的 maccms 目录
COPY ./maccms.conf /etc/apache2/sites-available/maccms.conf
# 禁用默认站点，启用 maccms 站点和 rewrite 模块
RUN a2dissite 000-default.conf && a2ensite maccms.conf && a2enmod rewrite

# --------------------------------------------------------------------
# 第四阶段：安装并配置 MySQL 
# --------------------------------------------------------------------
# 设置 MySQL root 用户的免密登录，方便后续脚本操作
RUN mkdir -p /etc/mysql/conf.d \
    && echo '[mysqld]' > /etc/mysql/conf.d/disable_auth.cnf \
    && echo 'skip-grant-tables' >> /etc/mysql/conf.d/disable_auth.cnf

# 通过 policy-rc.d 阻止服务在安装时自动启动，这是 Dockerfile 最佳实践
RUN echo 'exit 101' > /usr/sbin/policy-rc.d && chmod +x /usr/sbin/policy-rc.d

# 安装 MySQL 服务
RUN apt-get update && apt-get install -y --no-install-recommends mysql-server \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# 安装完成后，移除策略文件，以免影响容器运行
RUN rm /usr/sbin/policy-rc.d

# 修改 MySQL 默认数据目录，指向持久化卷
RUN sed -i 's|/var/lib/mysql|/var/www/html/mysql|g' /etc/mysql/mysql.conf.d/mysqld.cnf
# --------------------------------------------------------------------
# 第五阶段：配置 Supervisor 和 SSH
# --------------------------------------------------------------------
# 配置 Supervisor，让其包含持久化卷中的配置文件
# 我们不在镜像里放任何具体的服务 conf，只配置 include 路径
RUN mkdir -p /var/log/supervisor \
    && echo '[include]' >> /etc/supervisor/supervisord.conf \
    && echo 'files = /var/www/html/supervisor/conf.d/*.conf' >> /etc/supervisor/supervisord.conf

# 配置 SSH，允许 root 登录（密码设置在 entrypoint.sh 中进行）
RUN sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config \
    && sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config \
    # SSH 守护进程需要 /run/sshd 目录
    && mkdir -p /run/sshd

# --------------------------------------------------------------------
# 第六阶段：设置入口点和默认命令
# --------------------------------------------------------------------
# 拷贝启动脚本并赋予执行权限
COPY ./entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# 暴露 Apache 的 80 端口
EXPOSE 80

# 定义容器入口点
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

# 默认执行的命令，交由 entrypoint 脚本的末尾执行
# -n 参数让 supervisord 在前台运行，这是容器化所必须的
CMD ["/usr/bin/supervisord", "-n", "-c", "/etc/supervisor/supervisord.conf"]
