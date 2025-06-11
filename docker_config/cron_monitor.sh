#!/bin/bash
# cron任务文件监控脚本 - 使用inotifywait高效监控

CRON_FILE_NAME="maccms_cron"
CRON_DIR="/var/www/html/cron"
CRON_FILE_PATH="${CRON_DIR}/${CRON_FILE_NAME}"

echo "启动cron任务高效监控..."

# 首次启动时，如果cron文件存在，先加载一次
if [ -f "$CRON_FILE_PATH" ]; then
    echo "检测到cron文件存在，进行初始加载..."
    crontab "$CRON_FILE_PATH"
    echo "初始加载完成。"
fi

# 使用inotifywait持续监控目录中的文件变化
# -m: 持续监控，不退出
# -e create,modify,moved_to: 关注文件被创建、修改、或移入目录的事件
# --format '%f': 只输出触发事件的文件名
while true; do
  inotifywait -m -e create,modify,moved_to --format '%f' "${CRON_DIR}" | while read FILENAME; do
    # 判断发生变化的文件是否是我们需要监控的目标文件
    if [ "$FILENAME" = "$CRON_FILE_NAME" ]; then
      echo "检测到 '${CRON_FILE_NAME}' 文件发生变化，重新加载..."
      # 等待一秒，防止文件还在写入中
      sleep 1 
      crontab "$CRON_FILE_PATH"
      echo "cron任务已更新。"
    fi
  done
  # 如果inotifywait因故退出（例如目录被删除后重建），等待后重新循环
  echo "监控进程中断，5秒后尝试重启..."
  sleep 5
done
