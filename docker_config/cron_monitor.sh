#!/bin/bash
# cron任务文件监控脚本 - 实时同步maccms_cron文件变化

CRON_FILE="/var/www/html/cron/maccms_cron"
LAST_MODIFIED=""

echo "启动cron任务监控..."

while true; do
    if [ -f "$CRON_FILE" ]; then
        CURRENT_MODIFIED=$(stat -c %Y "$CRON_FILE" 2>/dev/null)
        if [ "$CURRENT_MODIFIED" != "$LAST_MODIFIED" ]; then
            echo "检测到cron文件变化，重新加载..."
            crontab "$CRON_FILE"
            LAST_MODIFIED="$CURRENT_MODIFIED"
            echo "cron任务已更新"
        fi
    fi
    sleep 30  # 每30秒检查一次
done
