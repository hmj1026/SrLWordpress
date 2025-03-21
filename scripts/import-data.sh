#!/bin/bash

# 檢查參數
if [ "$#" -ne 2 ]; then
    echo "使用方法: $0 <database_backup.sql> <wordpress_backup.tar.gz>"
    exit 1
fi

DB_BACKUP=$1
WP_BACKUP=$2
MYSQL_CONTAINER="wp_db"
WP_CONTAINER="wp_app"

# 檢查備份文件是否存在
if [ ! -f "$DB_BACKUP" ] || [ ! -f "$WP_BACKUP" ]; then
    echo "錯誤：備份文件不存在"
    exit 1
fi

# 匯入資料庫
echo "正在匯入資料庫..."
docker exec -i $MYSQL_CONTAINER mysql -u${MYSQL_USER} -p${MYSQL_PASSWORD} ${MYSQL_DATABASE} < "$DB_BACKUP"

# 解壓 WordPress 備份
echo "正在解壓 WordPress 備份..."
TEMP_DIR=$(mktemp -d)
tar -xzf "$WP_BACKUP" -C "$TEMP_DIR"

# 找到解壓後的目錄
EXTRACTED_DIR=$(find "$TEMP_DIR" -type d -name "wp_backup_*")

# 匯入 WordPress 文件
echo "正在匯入 WordPress 文件..."
docker cp "$EXTRACTED_DIR/plugins" $WP_CONTAINER:/var/www/html/wp-content/
docker cp "$EXTRACTED_DIR/themes" $WP_CONTAINER:/var/www/html/wp-content/
docker cp "$EXTRACTED_DIR/wp-config.php" $WP_CONTAINER:/var/www/html/

# 設定權限
docker exec $WP_CONTAINER chown -R www-data:www-data /var/www/html

# 清理臨時文件
rm -rf "$TEMP_DIR"

echo "匯入完成！"
echo "請檢查網站是否正常運作。"
