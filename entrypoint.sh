#!/bin/bash
set -e

#==============================================================================
# 1. 配置 SSH 用户与密码
#==============================================================================
echo "[入口点脚本] 正在设置 SSH 用户 'admin'..."
# 创建一个名为 'admin' 的非 root 用户，并赋予 sudo 权限
useradd -m -s /bin/bash admin || echo "用户 admin 已存在"
usermod -aG sudo admin

# 从环境变量 SSH_PASSWORD 设置密码，如果变量未设置，则使用默认值
SSH_USER_PASSWORD=${SSH_PASSWORD:-admin123}
echo "admin:${SSH_USER_PASSWORD}" | chpasswd
echo "[入口点脚本] SSH 用户 'admin' 的密码已设置。"

#==============================================================================
# 2. 首次运行时初始化 MYSQL 数据库
#==============================================================================
# 检查 mysql 数据目录是否已被初始化
if [ ! -d "/var/www/html/mysql/mysql" ]; then
    echo "[入口点脚本] 首次运行 MySQL，正在 /var/www/html/mysql 目录中初始化数据库..."

    # 确保目录存在并为 'mysql' 用户设置正确权限
    mkdir -p /var/www/html/mysql
    chown -R mysql:mysql /var/www/html/mysql

    # 初始化数据库。--initialize-insecure 会创建一个无密码的 root 用户。
    mysqld --initialize-insecure --user=mysql --datadir=/var/www/html/mysql

    echo "[入口点脚本] MySQL 数据库初始化完成。正在启动临时服务以设置密码..."

    # 在后台启动 MySQL 服务
    mysqld --user=mysql --datadir=/var/www/html/mysql &
    MYSQL_PID=$!

    # 等待服务就绪
    retries=30
    while ! mysqladmin ping --silent && [ $retries -gt 0 ]; do
        echo "正在等待 MySQL 服务启动... (剩余尝试次数: $retries)"
        sleep 2
        retries=$((retries-1))
    done
    if [ $retries -eq 0 ]; then
        echo "[错误] MySQL 服务启动失败。"
        exit 1
    fi

    echo "[入口点脚本] MySQL 服务已启动。正在进行安全设置..."

    # 从环境变量设置密码，如果未提供则使用默认值
    MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD:-root_password}
    MACCMS_DB_NAME=${MACCMS_DB_NAME:-maccms}
    MACCMS_DB_USER=${MACCMS_DB_USER:-maccms_user}
    MACCMS_DB_PASSWORD=${MACCMS_DB_PASSWORD:-maccms_password}

    # 设置 root 密码并创建 maccms 数据库和用户
    mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';"
    mysql -e "CREATE DATABASE IF NOT EXISTS \`${MACCMS_DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
    mysql -e "CREATE USER IF NOT EXISTS '${MACCMS_DB_USER}'@'%' IDENTIFIED BY '${MACCMS_DB_PASSWORD}';"
    mysql -e "GRANT ALL PRIVILEGES ON \`${MACCMS_DB_NAME}\`.* TO '${MACCMS_DB_USER}'@'%';"
    mysql -e "FLUSH PRIVILEGES;"

    echo "[入口点脚本] MySQL 的 root 密码以及 maccms 数据库/用户已创建。"
    echo "  - Root 密码: ${MYSQL_ROOT_PASSWORD}"
    echo "  - Maccms 数据库: ${MACCMS_DB_NAME}, 用户: ${MACCMS_DB_USER}, 密码: ${MACCMS_DB_PASSWORD}"

    # 关闭临时服务
    mysqladmin -u root -p"${MYSQL_ROOT_PASSWORD}" shutdown
    wait $MYSQL_PID
    echo "[入口点脚本] MySQL 初始化流程完成。"
else
    echo "[入口点脚本] MySQL 数据库已存在，跳过初始化步骤。"
fi


#==============================================================================
# 3. 设置目录权限
#==============================================================================
echo "[入口点脚本] 正在设置最终的目录权限..."
# Apache/PHP 需要对 maccms 目录有写入权限
chown -R www-data:www-data /var/www/html/maccms

# 确保其他受管理的目录存在
mkdir -p /var/www/html/cron
mkdir -p /var/www/html/supervisor/conf.d

#==============================================================================
# 4. 执行容器的主命令
#==============================================================================
echo "[入口点脚本] 所有任务完成，现在将控制权交给 Supervisor..."
# 执行 Dockerfile 中 CMD 定义的命令 (或者传递给 `docker run` 的命令)
exec "$@"
