#!/bin/bash

# 設定變數
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="backups"
MYSQL_CONTAINER="wp_db"
WP_CONTAINER="wp_app"

# 創建備份目錄
mkdir -p $BACKUP_DIR

# 匯出資料庫
echo "正在匯出資料庫..."
docker exec $MYSQL_CONTAINER mysqldump --no-tablespaces -u${MYSQL_USER} -p${MYSQL_PASSWORD} ${MYSQL_DATABASE} > "$BACKUP_DIR/database_$TIMESTAMP.sql"

# 匯出 WordPress 設定和插件
echo "正在匯出 WordPress 設定..."

# 建立臨時目錄
mkdir -p "$BACKUP_DIR/wp_backup_$TIMESTAMP"

# 複製重要的 WordPress 文件和目錄
docker cp $WP_CONTAINER:/var/www/html/wp-content/plugins "$BACKUP_DIR/wp_backup_$TIMESTAMP/"
docker cp $WP_CONTAINER:/var/www/html/wp-content/themes "$BACKUP_DIR/wp_backup_$TIMESTAMP/"
docker cp $WP_CONTAINER:/var/www/html/wp-config.php "$BACKUP_DIR/wp_backup_$TIMESTAMP/"

# 創建壓縮檔
tar -czf "$BACKUP_DIR/wp_backup_$TIMESTAMP.tar.gz" -C "$BACKUP_DIR" "wp_backup_$TIMESTAMP"

# 清理臨時目錄
rm -rf "$BACKUP_DIR/wp_backup_$TIMESTAMP"

echo "備份完成！文件保存在 $BACKUP_DIR 目錄下："
echo "- 資料庫備份：database_$TIMESTAMP.sql"
echo "- WordPress 備份：wp_backup_$TIMESTAMP.tar.gz"
