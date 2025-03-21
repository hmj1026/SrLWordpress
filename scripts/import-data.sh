#!/bin/bash
# 啟用嚴格模式
set -euo pipefail

# 檢查參數
if [ "$#" -ne 1 ]; then
    echo "使用方法: $0 <backup.tar.gz>"
    echo "注意：請確保對應的 .tar.gz.sha256 檔案存在於同一目錄"
    exit 1
fi

BACKUP_FILE="$1"
MYSQL_CONTAINER="${MYSQL_CONTAINER:-wp_db}"
WP_CONTAINER="${WP_CONTAINER:-wp_app}"

# 檢查備份檔案是否存在
if [ ! -f "$BACKUP_FILE" ]; then
    echo "錯誤：備份檔案 $BACKUP_FILE 不存在"
    exit 1
fi

# 檢查校驗碼檔案
CHECKSUM_FILE="$BACKUP_FILE.sha256"
if [ -f "$CHECKSUM_FILE" ]; then
    echo "▶ 驗證備份檔案完整性..."
    sha256sum -c "$CHECKSUM_FILE" || { echo "錯誤：備份檔案校驗失敗"; exit 1; }
else
    echo "警告：未找到校驗碼檔案 $CHECKSUM_FILE，跳過完整性檢查"
fi

# 載入 .env 檔案
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${ENV_FILE:-$SCRIPT_DIR/../.env}"
if [ -f "$ENV_FILE" ]; then
    echo "▶ 載入環境變數從 $ENV_FILE..."
    set -a
    source "$ENV_FILE"
    set +a
else
    echo "警告：$ENV_FILE 檔案不存在，將依賴外部環境變數"
fi

# 檢查必要環境變數
: ${MYSQL_USER:?必須設定 MYSQL_USER 環境變數}
: ${MYSQL_PASSWORD:?必須設定 MYSQL_PASSWORD 環境變數}
: ${MYSQL_DATABASE:?必須設定 MYSQL_DATABASE 環境變數}

# 解壓備份檔案
echo "▶ 解壓備份檔案 $BACKUP_FILE..."
TEMP_DIR=$(mktemp -d)
tar -xzf "$BACKUP_FILE" -C "$TEMP_DIR" || { echo "錯誤：解壓失敗"; exit 1; }

# 找到解壓後的目錄
EXTRACTED_DIR=$(find "$TEMP_DIR" -maxdepth 1 -type d -name "backup_*" | head -n 1)
if [ -z "$EXTRACTED_DIR" ]; then
    echo "錯誤：未找到預期的 backup_* 目錄"
    rm -rf "$TEMP_DIR"
    exit 1
fi

# 匯入資料庫
DB_BACKUP="$EXTRACTED_DIR/database.sql"
if [ -f "$DB_BACKUP" ]; then
    echo "  ▷ 匯入資料庫..."
    # 使用唯一臨時檔案名稱
    MYSQL_CRED_FILE="${TEMP_DIR}/.mysql_restore_$$.cnf"
    cat > "$MYSQL_CRED_FILE" << EOF
[client]
user=${MYSQL_USER}
password=${MYSQL_PASSWORD}
EOF
    chmod 600 "$MYSQL_CRED_FILE"
    
    # 嘗試使用認證檔案匯入，若失敗則回退到直接連線
    if docker cp "$MYSQL_CRED_FILE" "$MYSQL_CONTAINER:/etc/mysql/conf.d/" 2>/dev/null; then
        docker exec -i "$MYSQL_CONTAINER" mysql \
            --defaults-extra-file=/etc/mysql/conf.d/"$(basename "$MYSQL_CRED_FILE")" \
            "$MYSQL_DATABASE" < "$DB_BACKUP" || { echo "錯誤：資料庫匯入失敗"; rm -rf "$TEMP_DIR"; exit 1; }
        docker exec "$MYSQL_CONTAINER" rm -f /etc/mysql/conf.d/"$(basename "$MYSQL_CRED_FILE")"
    else
        echo "警告：無法複製認證檔案，改用直接連線方式"
        docker exec -i "$MYSQL_CONTAINER" mysql \
            -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" \
            "$MYSQL_DATABASE" < "$DB_BACKUP" || { echo "錯誤：資料庫匯入失敗"; rm -rf "$TEMP_DIR"; exit 1; }
    fi
    rm -f "$MYSQL_CRED_FILE"
else
    echo "錯誤：資料庫備份檔案 $DB_BACKUP 不存在"
    rm -rf "$TEMP_DIR"
    exit 1
fi

# 匯入 WordPress 檔案
echo "  ▷ 匯入 WordPress 檔案..."
docker cp "$EXTRACTED_DIR/wp-content" "$WP_CONTAINER:/var/www/html/" || { echo "錯誤：wp-content 匯入失敗"; rm -rf "$TEMP_DIR"; exit 1; }
docker cp "$EXTRACTED_DIR/wp-config.php" "$WP_CONTAINER:/var/www/html/" || { echo "錯誤：wp-config.php 匯入失敗"; rm -rf "$TEMP_DIR"; exit 1; }
if [ -f "$EXTRACTED_DIR/.htaccess" ]; then
    docker cp "$EXTRACTED_DIR/.htaccess" "$WP_CONTAINER:/var/www/html/" || echo "警告：.htaccess 匯入失敗"
else
    echo "  - 注意：備份中不含 .htaccess 檔案，跳過"
fi

# 設定權限
echo "  ▷ 設定檔案權限..."
docker exec "$WP_CONTAINER" chown -R www-data:www-data /var/www/html/ || { echo "錯誤：權限設定失敗"; rm -rf "$TEMP_DIR"; exit 1; }
docker exec "$WP_CONTAINER" chmod -R 755 /var/www/html/wp-content || { echo "錯誤：wp-content 權限設定失敗"; rm -rf "$TEMP_DIR"; exit 1; }

# 清理臨時檔案
echo "▶ 清理臨時檔案..."
rm -rf "$TEMP_DIR"

echo -e "\n✔ 匯入完成！"
echo "請檢查網站是否正常運作，並確認資料庫與檔案是否一致。"
