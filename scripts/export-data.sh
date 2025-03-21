#!/bin/bash
# 啟用嚴格模式
set -euo pipefail

# 可配置變數
readonly MYSQL_CONTAINER="${MYSQL_CONTAINER:-wp_db}"
readonly WP_CONTAINER="${WP_CONTAINER:-wp_app}"
readonly BACKUP_ROOT="${BACKUP_ROOT:-./backups}"
readonly TIMESTAMP=$(date +%Y%m%d_%H%M%S)
readonly BACKUP_DIR="$BACKUP_ROOT/backup_$TIMESTAMP"
readonly MYSQL_CRED_FILE="mysql_credentials.cnf"

# 載入 .env 檔案
# 預設路徑為腳本的上層目錄中的 .env
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${ENV_FILE:-$SCRIPT_DIR/../.env}"
if [ -f "$ENV_FILE" ]; then
    echo "▶ 載入環境變數從 $ENV_FILE..."
    set -a  # 自動將變數設為環境變數
    source "$ENV_FILE"
    set +a
else
    echo "警告：$ENV_FILE 檔案不存在，將依賴外部環境變數"
fi

# 錯誤處理函數
error_exit() {
    echo "錯誤：$1" >&2
    exit 1
}

# 清理臨時檔案函數（包含容器內檔案）
cleanup_temp() {
    rm -f "$MYSQL_CRED_FILE"
    docker exec "$MYSQL_CONTAINER" sh -c "rm -f /etc/mysql/conf.d/$MYSQL_CRED_FILE /tmp/database.sql" 2>/dev/null || true
    docker exec "$WP_CONTAINER" rm -rf /backup_tmp 2>/dev/null || true
}

# 檢查容器狀態並驗證工具
check_container() {
    docker inspect -f '{{.State.Running}}' "$1" >/dev/null 2>&1 || error_exit "容器 $1 未運行"
}

# 建立 MySQL 認證檔案
create_mysql_config() {
    cat > "$MYSQL_CRED_FILE" << EOF
[client]
user=${MYSQL_USER}
password=${MYSQL_PASSWORD}
EOF
    chmod 600 "$MYSQL_CRED_FILE"
    docker cp "$MYSQL_CRED_FILE" "$MYSQL_CONTAINER:/etc/mysql/conf.d/" || error_exit "無法複製 MySQL 設定檔"
}

# 詢問是否使用 --add-drop-database
prompt_add_drop_db() {
    read -p "是否在備份中加入 DROP DATABASE 語句？（預設為 N，輸入 Y 確認）: " response
    case "$response" in
        [Yy]*)
            echo "true"
            ;;
        *)
            echo "false"
            ;;
    esac
}

# 主備份流程
main() {
    # 檢查必要環境變數
    : ${MYSQL_USER:?必須設定 MYSQL_USER 環境變數}
    : ${MYSQL_PASSWORD:?必須設定 MYSQL_PASSWORD 環境變數}
    : ${MYSQL_DATABASE:?必須設定 MYSQL_DATABASE 環境變數}

    # 建立備份目錄
    mkdir -p "$BACKUP_DIR" || error_exit "無法建立備份目錄 $BACKUP_DIR"
    echo "▶ 開始備份流程..."

    # 檢查容器狀態
    check_container "$MYSQL_CONTAINER"
    check_container "$WP_CONTAINER"

    # 詢問是否加入 DROP DATABASE
    readonly ADD_DROP_DB=$(prompt_add_drop_db)

    # 資料庫備份
    echo "  ▷ 備份資料庫..."
    create_mysql_config
    MYSQLDUMP_OPTS="--defaults-extra-file=/etc/mysql/conf.d/$MYSQL_CRED_FILE --single-transaction --routines --triggers --no-tablespaces"
    if [ "$ADD_DROP_DB" = "true" ]; then
        echo "    - 啟用資料庫重建功能 (DROP/CREATE)"
        MYSQLDUMP_OPTS+=" --add-drop-database --databases $MYSQL_DATABASE"
    else
        echo "    - 使用快速備份模式 (僅資料)"
        MYSQLDUMP_OPTS+=" $MYSQL_DATABASE"
    fi
    echo -n "    備份進度..."
    if docker exec "$MYSQL_CONTAINER" sh -c "command -v pv >/dev/null 2>&1"; then
        docker exec "$MYSQL_CONTAINER" sh -c "mysqldump $MYSQLDUMP_OPTS | pv -W -N '資料庫備份' > /tmp/database.sql" \
            && docker cp "$MYSQL_CONTAINER:/tmp/database.sql" "$BACKUP_DIR/database.sql" \
            || error_exit "資料庫備份失敗"
    else
        docker exec "$MYSQL_CONTAINER" mysqldump $MYSQLDUMP_OPTS > "$BACKUP_DIR/database.sql" \
            || error_exit "資料庫備份失敗"
        echo "完成（無進度顯示）"
    fi

    # WordPress 檔案備份
    echo "  ▷ 備份 WordPress 檔案..."
    mkdir -p "$BACKUP_DIR/wp-content"
    if docker exec "$WP_CONTAINER" sh -c "command -v rsync >/dev/null 2>&1"; then
        echo "    - 使用 rsync 高效同步檔案..."
        docker exec "$WP_CONTAINER" mkdir -p /backup_tmp
        docker exec "$WP_CONTAINER" rsync -aAHX --delete --info=progress2 \
            /var/www/html/wp-content/ /backup_tmp/wp-content/ \
            || error_exit "wp-content 同步失敗"
        docker exec "$WP_CONTAINER" rsync -aAHX --delete \
            /var/www/html/wp-config.php /backup_tmp/ \
            || error_exit "wp-config.php 同步失敗"
        docker exec "$WP_CONTAINER" rsync -aAHX --delete \
            /var/www/html/.htaccess /backup_tmp/ 2>/dev/null || echo "    警告：.htaccess 檔案不存在"
        docker cp "$WP_CONTAINER:/backup_tmp" "$BACKUP_DIR/" || error_exit "檔案拷貝失敗"
    else
        echo "    - rsync 不可用，使用標準方式備份..."
        docker cp "$WP_CONTAINER:/var/www/html/wp-content" "$BACKUP_DIR/" || error_exit "wp-content 備份失敗"
        docker cp "$WP_CONTAINER:/var/www/html/wp-config.php" "$BACKUP_DIR/" || error_exit "wp-config.php 備份失敗"
        docker cp "$WP_CONTAINER:/var/www/html/.htaccess" "$BACKUP_DIR/" 2>/dev/null || echo "    警告：.htaccess 檔案不存在"
    fi

    # 生成校驗碼
    echo "  ▷ 生成檔案校驗碼..."
    sha256sum "$BACKUP_DIR"/*/* "$BACKUP_DIR"/* > "$BACKUP_DIR/checksums.sha256" 2>/dev/null || true

    # 壓縮備份
    echo "  ▷ 壓縮備份檔案..."
    tar -czf "$BACKUP_DIR.tar.gz" -C "$BACKUP_ROOT" "backup_$TIMESTAMP" || error_exit "壓縮失敗"
    sha256sum "$BACKUP_DIR.tar.gz" > "$BACKUP_DIR.tar.gz.sha256"

    # 清理臨時檔案
    cleanup_temp
    rm -rf "$BACKUP_DIR"

    echo -e "\n✔ 備份成功完成！"
    echo "備份檔案位置：$BACKUP_DIR.tar.gz"
    echo "檔案大小：$(du -h "$BACKUP_DIR.tar.gz" | cut -f1)"
    echo "校驗碼檔案：$BACKUP_DIR.tar.gz.sha256"
    if [ "$ADD_DROP_DB" = "true" ]; then
        echo "注意：此備份包含 DROP DATABASE 語句，還原時將覆蓋目標資料庫。"
    fi
}

# 捕捉錯誤以確保清理
trap 'cleanup_temp' EXIT

# 執行備份
main