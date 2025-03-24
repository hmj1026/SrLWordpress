#!/bin/bash

# 設定你的容器名稱
DB_CONTAINER="wp_db"

echo "🔍 檢查容器是否存在：$DB_CONTAINER"
if ! docker ps --format '{{.Names}}' | grep -q "^${DB_CONTAINER}$"; then
    echo "❌ 找不到容器 $DB_CONTAINER，請確認容器名稱是否正確"
    exit 1
fi

echo "🚪 進入容器：$DB_CONTAINER"

# 確認是否已有 mysql-client
echo "🔍 檢查是否已安裝 mysqldump..."
if docker exec "$DB_CONTAINER" sh -c "command -v mysqldump >/dev/null 2>&1"; then
    echo "✅ 容器內已安裝 mysqldump，無需重複安裝"
    exit 0
fi

# 安裝 mariadb-client（含 mysqldump）
echo "📦 開始安裝 mariadb-client..."
docker exec "$DB_CONTAINER" sh -c "apk update && apk add --no-cache mariadb-client" || {
    echo "❌ 安裝失敗，可能不是 Alpine 基底或網路有問題"
    exit 1
}

echo "✅ 安裝完成！你現在可以在容器內使用 mysqldump 囉～"