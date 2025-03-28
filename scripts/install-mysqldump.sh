#!/bin/bash

DB_CONTAINER="wp_db"

echo "🔍 檢查容器是否存在：$DB_CONTAINER"
if ! docker ps --format '{{.Names}}' | grep -q "^${DB_CONTAINER}$"; then
    echo "❌ 找不到容器 $DB_CONTAINER，請確認容器名稱是否正確"
    exit 1
fi

echo "🚪 進入容器：$DB_CONTAINER"

echo "🔍 檢查是否已安裝 mysqldump..."
if docker exec "$DB_CONTAINER" sh -c "command -v mysqldump >/dev/null 2>&1"; then
    echo "✅ 容器內已安裝 mysqldump，無需重複安裝"
    exit 0
fi

echo "📦 嘗試安裝 mysqldump..."
docker exec "$DB_CONTAINER" sh -c '
    if command -v apk >/dev/null 2>&1; then
        apk update && apk add --no-cache mariadb-client
    elif command -v apt-get >/dev/null 2>&1; then
        apt-get update && apt-get install -y default-mysql-client
    elif command -v yum >/dev/null 2>&1; then
        yum install -y mysql
    else
        echo "❌ 不支援的套件管理器"; exit 1
    fi
' || {
    echo "❌ 安裝失敗，請確認容器基底或網路連線"
    exit 1
}

echo "✅ 安裝完成！你現在可以使用 mysqldump 囉～"