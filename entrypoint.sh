#!/bin/bash
# 遇到任何错误则立即退出
set -e

echo "================================================="
echo "               容器启动脚本执行中...             "
echo "================================================="

# 1. 设置 SSH root 密码
# 如果环境变量 SSH_PASSWORD 未设置，则使用默认密码 'admin123'
SSH_PASSWORD=${SSH_PASSWORD:-admin123}
echo "root:$SSH_PASSWORD" | chpasswd
echo "-> SSH root 密码已设置。"
echo "   - 用户名: root"
echo "   - 密  码: ${SSH_PASSWORD}"

# 2. 初始化 MySQL 数据库
# 检查持久化目录中是否已存在数据库文件
if [ ! -d "/var/www/html/mysql/mysql" ]; then
    echo "-> 检测到 MySQL 数据目录为空，正在进行首次初始化..."
    # 确保目录存在且权限正确
    mkdir -p /var/www/html/mysql
    chown -R mysql:mysql /var/www/html/mysql

    # 使用 --initialize-insecure 初始化，不生成临时 root 密码
    mysqld --initialize-insecure --user=mysql --datadir=/var/www/html/mysql
    echo "-> MySQL 初始化完成。"
else
    echo "-> MySQL 数据已存在，跳过初始化。"
    # 即使已存在，也需确保权限正确
    chown -R mysql:mysql /var/www/html/mysql
fi

# 3. 加载 Cron 定时任务
# 检查持久化目录中是否存在 cron 配置文件
if [ -f "/var/www/html/cron/maccms_cron" ]; then
    echo "-> 正在加载 Cron 定时任务..."
    # 加载任务文件到系统 cron
    crontab /var/www/html/cron/maccms_cron
    # 确保 cron 文件可读
    chmod 0644 /var/www/html/cron/maccms_cron
    echo "-> Cron 任务已从 /var/www/html/cron/maccms_cron 加载。"
else
    echo "-> 未找到 /var/www/html/cron/maccms_cron 文件，跳过加载。"
fi

# 4. 设置 Web 目录权限
if [ -d "/var/www/html/maccms" ]; then
    echo "-> 正在设置 /var/www/html/maccms 目录权限..."
    # 将 maccms 目录的所有权交给 apache 的运行用户 www-data
    chown -R www-data:www-data /var/www/html/maccms
    echo "-> 目录权限设置完成。"
else
    echo "-> 警告：未找到 /var/www/html/maccms 目录！"
fi

echo "================================================="
echo "             初始化完成，启动主进程...           "
echo "================================================="
echo ""

# 执行 Dockerfile 中 CMD 定义的命令 (即 supervisord)
exec "$@"
