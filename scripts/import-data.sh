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

# 檢查必要檔案是否存在
for required_file in "database.sql" "wp-config.php" "wp-content"; do
    if [ ! -e "$EXTRACTED_DIR/$required_file" ]; then
        echo "錯誤：備份中缺少必要檔案 $required_file"
        rm -rf "$TEMP_DIR"
        exit 1
    fi
done

# 匯入資料庫
DB_BACKUP="$EXTRACTED_DIR/database.sql"
echo "  ▷ 匯入資料庫..."
# 使用唯一臨時檔案名稱
MYSQL_CRED_FILE="${TEMP_DIR}/.mysql_restore_$$.cnf"
cat > "$MYSQL_CRED_FILE" << EOF
[client]
user=${MYSQL_USER}
password=${MYSQL_PASSWORD}
EOF
chmod 600 "$MYSQL_CRED_FILE"

# 檢查資料庫是否包含 DROP DATABASE 語句
if grep -q "DROP DATABASE" "$DB_BACKUP"; then
    echo "    - 檢測到 DROP DATABASE 語句，將重建資料庫"
    HAS_DROP_DB=true
else
    echo "    - 未檢測到 DROP DATABASE 語句，使用標準匯入"
    HAS_DROP_DB=false
fi

# 嘗試使用認證檔案匯入，若失敗則回退到直接連線
if docker cp "$MYSQL_CRED_FILE" "$MYSQL_CONTAINER:/etc/mysql/conf.d/" 2>/dev/null; then
    # 如果包含 DROP DATABASE，需要確保有足夠權限
    if [ "$HAS_DROP_DB" = true ]; then
        echo "    - 使用管理員權限匯入資料庫..."
        docker exec -i "$MYSQL_CONTAINER" mysql \
            --defaults-extra-file=/etc/mysql/conf.d/"$(basename "$MYSQL_CRED_FILE")" \
            < "$DB_BACKUP" || { echo "錯誤：資料庫匯入失敗"; rm -rf "$TEMP_DIR"; exit 1; }
    else
        docker exec -i "$MYSQL_CONTAINER" mysql \
            --defaults-extra-file=/etc/mysql/conf.d/"$(basename "$MYSQL_CRED_FILE")" \
            "$MYSQL_DATABASE" < "$DB_BACKUP" || { echo "錯誤：資料庫匯入失敗"; rm -rf "$TEMP_DIR"; exit 1; }
    fi
    docker exec "$MYSQL_CONTAINER" rm -f /etc/mysql/conf.d/"$(basename "$MYSQL_CRED_FILE")"
else
    echo "警告：無法複製認證檔案，改用直接連線方式"
    if [ "$HAS_DROP_DB" = true ]; then
        docker exec -i "$MYSQL_CONTAINER" mysql \
            -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" \
            < "$DB_BACKUP" || { echo "錯誤：資料庫匯入失敗"; rm -rf "$TEMP_DIR"; exit 1; }
    else
        docker exec -i "$MYSQL_CONTAINER" mysql \
            -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" \
            "$MYSQL_DATABASE" < "$DB_BACKUP" || { echo "錯誤：資料庫匯入失敗"; rm -rf "$TEMP_DIR"; exit 1; }
    fi
fi
rm -f "$MYSQL_CRED_FILE"

# 匯入 WordPress 檔案
echo "  ▷ 匯入 WordPress 檔案..."
echo "    - 驗證檔案完整性..."
if [ -f "$EXTRACTED_DIR/checksums.sha256" ]; then
    # 計算檔案總數
    TOTAL_FILES=$(grep -v "checksums.sha256" "$EXTRACTED_DIR/checksums.sha256" | wc -l)
    echo "      總計 $TOTAL_FILES 個檔案需要驗證"
    
    # 顯示進度條
    echo -n "      驗證進度: [          ] 0%"
    
    # 使用臨時檔案記錄進度
    PROGRESS_FILE=$(mktemp)
    
    # 在背景執行驗證，同時更新進度
    (
        cd "$EXTRACTED_DIR"
        COUNTER=0
        while IFS= read -r line; do
            FILENAME=$(echo "$line" | awk '{print $2}')
            if [ "$FILENAME" != "checksums.sha256" ]; then
                sha256sum --quiet -c <(echo "$line") 2>/dev/null
                echo $((++COUNTER)) > "$PROGRESS_FILE"
            fi
        done < checksums.sha256
    ) &
    
    # 顯示進度
    VERIFICATION_PID=$!
    while kill -0 $VERIFICATION_PID 2>/dev/null; do
        if [ -f "$PROGRESS_FILE" ]; then
            CURRENT=$(cat "$PROGRESS_FILE")
            PERCENT=$((CURRENT * 100 / TOTAL_FILES))
            BARS=$((PERCENT / 10))
            SPACES=$((10 - BARS))
            PROGRESS="["
            for ((i=0; i<BARS; i++)); do PROGRESS="${PROGRESS}#"; done
            for ((i=0; i<SPACES; i++)); do PROGRESS="${PROGRESS} "; done
            PROGRESS="${PROGRESS}] ${PERCENT}%"
            echo -ne "\r      驗證進度: $PROGRESS"
        fi
        sleep 0.5
    done
    
    # 檢查驗證結果
    wait $VERIFICATION_PID
    VERIFY_STATUS=$?
    echo -e "\r      驗證進度: [##########] 100%"
    rm -f "$PROGRESS_FILE"
    
    if [ $VERIFY_STATUS -ne 0 ]; then
        echo "錯誤：檔案完整性驗證失敗"; 
        rm -rf "$TEMP_DIR"; 
        exit 1;
    else
        echo "      ✓ 所有檔案驗證成功"
    fi
else
    echo "警告：未找到校驗碼檔案，跳過完整性檢查"
fi

# 備份現有 WordPress 檔案（以防還原失敗）
echo "    - 備份現有 WordPress 設定..."
RESTORE_TIMESTAMP=$(date +%Y%m%d_%H%M%S)
docker exec "$WP_CONTAINER" sh -c "if [ -d /var/www/html/wp-content ]; then \
    mkdir -p /tmp/wp_backup_$RESTORE_TIMESTAMP && \
    cp -a /var/www/html/wp-config.php /var/www/html/.htaccess /tmp/wp_backup_$RESTORE_TIMESTAMP/ 2>/dev/null || true; \
fi"

echo "    - 還原 wp-content..."
# 計算檔案大小
WP_CONTENT_SIZE=$(du -sh "$EXTRACTED_DIR/wp-content" | cut -f1)
echo "      wp-content 目錄大小: $WP_CONTENT_SIZE"

# 移除舊目錄
docker exec "$WP_CONTAINER" rm -rf /var/www/html/wp-content

# 使用 pv 顯示進度 (如果可用)
if command -v pv >/dev/null 2>&1; then
    echo "      開始傳輸檔案 (請稍候)..."
    tar -C "$EXTRACTED_DIR" -cf - wp-content | pv -s $(du -sb "$EXTRACTED_DIR/wp-content" | awk '{print $1}') | \
    docker exec -i "$WP_CONTAINER" tar -xf - -C /var/www/html/ || { 
        echo "錯誤：wp-content 匯入失敗，嘗試還原備份"; 
        docker exec "$WP_CONTAINER" sh -c "if [ -d /tmp/wp_backup_$RESTORE_TIMESTAMP ]; then \
            cp -a /tmp/wp_backup_$RESTORE_TIMESTAMP/* /var/www/html/ 2>/dev/null || true; \
        fi"
        rm -rf "$TEMP_DIR"; 
        exit 1; 
    }
else
    # 顯示進度點
    echo -n "      傳輸進度: "
    docker cp "$EXTRACTED_DIR/wp-content" "$WP_CONTAINER:/var/www/html/" &
    CP_PID=$!
    while kill -0 $CP_PID 2>/dev/null; do
        echo -n "."
        sleep 1
    done
    wait $CP_PID
    CP_STATUS=$?
    echo " 完成"
    
    if [ $CP_STATUS -ne 0 ]; then
        echo "錯誤：wp-content 匯入失敗，嘗試還原備份"; 
        docker exec "$WP_CONTAINER" sh -c "if [ -d /tmp/wp_backup_$RESTORE_TIMESTAMP ]; then \
            cp -a /tmp/wp_backup_$RESTORE_TIMESTAMP/* /var/www/html/ 2>/dev/null || true; \
        fi"
        rm -rf "$TEMP_DIR"; 
        exit 1;
    fi
fi

echo "    - 還原設定檔..."
docker cp "$EXTRACTED_DIR/wp-config.php" "$WP_CONTAINER:/var/www/html/" || { echo "錯誤：wp-config.php 匯入失敗"; rm -rf "$TEMP_DIR"; exit 1; }

if [ -f "$EXTRACTED_DIR/.htaccess" ]; then
    echo "    - 還原 .htaccess..."
    docker cp "$EXTRACTED_DIR/.htaccess" "$WP_CONTAINER:/var/www/html/" || { echo "警告：.htaccess 匯入失敗，嘗試手動建立"; docker exec "$WP_CONTAINER" touch /var/www/html/.htaccess; }
else
    echo "    - 注意：備份中不含 .htaccess 檔案，已建立空白檔案"
    docker exec "$WP_CONTAINER" touch /var/www/html/.htaccess
fi

# 設定權限
echo "  ▷ 設定檔案權限..."
docker exec "$WP_CONTAINER" chown -R www-data:www-data /var/www/html/ || { echo "錯誤：權限設定失敗"; rm -rf "$TEMP_DIR"; exit 1; }
docker exec "$WP_CONTAINER" find /var/www/html/wp-content -type d -exec chmod 755 {} \; || { echo "警告：目錄權限設定失敗"; }
docker exec "$WP_CONTAINER" find /var/www/html/wp-content -type f -exec chmod 644 {} \; || { echo "警告：檔案權限設定失敗"; }

# 清理臨時檔案
echo "▶ 清理臨時檔案..."
rm -rf "$TEMP_DIR"
docker exec "$WP_CONTAINER" rm -rf /tmp/wp_backup_$RESTORE_TIMESTAMP 2>/dev/null || true

# 驗證還原結果
echo "  ▷ 驗證還原結果..."
if docker exec "$WP_CONTAINER" [ -d "/var/www/html/wp-content" ] && \
   docker exec "$WP_CONTAINER" [ -f "/var/www/html/wp-config.php" ]; then
    echo "    - 檔案結構驗證成功"
else
    echo "警告：檔案結構驗證失敗，請手動檢查"
fi

# 嘗試驗證資料庫連接
echo "    - 驗證資料庫連接..."
if docker exec "$WP_CONTAINER" php -r "
    \$config = file_get_contents('/var/www/html/wp-config.php');
    preg_match('/define\(\s*[\'\"](DB_NAME)[\'\"],\s*[\'\"]([^\'\"]+)[\'\"]\s*\)/i', \$config, \$matches);
    \$db_name = \$matches[2];
    preg_match('/define\(\s*[\'\"](DB_USER)[\'\"],\s*[\'\"]([^\'\"]+)[\'\"]\s*\)/i', \$config, \$matches);
    \$db_user = \$matches[2];
    preg_match('/define\(\s*[\'\"](DB_PASSWORD)[\'\"],\s*[\'\"]([^\'\"]+)[\'\"]\s*\)/i', \$config, \$matches);
    \$db_pass = \$matches[2];
    preg_match('/define\(\s*[\'\"](DB_HOST)[\'\"],\s*[\'\"]([^\'\"]+)[\'\"]\s*\)/i', \$config, \$matches);
    \$db_host = \$matches[2];
    \$conn = new mysqli(\$db_host, \$db_user, \$db_pass, \$db_name);
    exit(\$conn->connect_error ? 1 : 0);
" 2>/dev/null; then
    echo "    - 資料庫連接驗證成功"
else
    echo "警告：資料庫連接驗證失敗，請檢查 wp-config.php 中的資料庫設定"
fi

echo -e "\n✔ 匯入完成！"
echo "請檢查網站是否正常運作，並確認資料庫與檔案是否一致。"
echo "如需重新整理快取，請執行：docker-compose restart wordpress"
