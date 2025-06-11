#!/bin/bash
# 容器启动脚本 - 遵循项目规范的初始化流程

# 设置SSH root密码（通过环境变量SSH_PASSWORD传递，默认admin123）
SSH_PASSWORD=${SSH_PASSWORD:-admin123}
echo "root:$SSH_PASSWORD" | chpasswd
echo "SSH root密码已设置"

# 初始化MySQL数据目录（如果为空）
if [ ! -d "/var/www/html/mysql/mysql" ]; then
    echo "初始化MySQL数据目录..."
    mysqld --initialize-insecure --user=mysql --datadir=/var/www/html/mysql
    echo "MySQL数据目录初始化完成"
fi

# 加载cron任务（从持久化目录）
if [ -f "/var/www/html/cron/maccms_cron" ]; then
    echo "加载cron任务..."
    crontab /var/www/html/cron/maccms_cron
    echo "cron任务加载完成"
else
    echo "警告: /var/www/html/cron/maccms_cron 文件不存在"
fi

# 启动cron任务监控脚本（后台运行）
/usr/local/bin/cron_monitor.sh &

# 启动Supervisor（前台运行）
echo "启动Supervisor服务管理器..."
exec /usr/bin/supervisord -c /etc/supervisor/supervisord.conf
