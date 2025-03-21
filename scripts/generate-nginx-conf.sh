#!/bin/bash

# 詢問專案名稱
read -p "請輸入專案名稱: " PROJECT_NAME
if [ -z "$PROJECT_NAME" ]; then
    echo "錯誤：專案名稱不能為空"
    exit 1
fi

# 詢問域名
read -p "請輸入域名 (NGINX_HOST): " NGINX_HOST
if [ -z "$NGINX_HOST" ]; then
    echo "錯誤：域名不能為空"
    exit 1
fi

# 詢問環境類型
echo "請選擇環境類型："
echo "1) 開發環境 (dev)"
echo "2) 生產環境 (prod)"
read -p "請輸入選項 (1 或 2): " env_choice

case $env_choice in
    1)
        ENV_TYPE="dev"
        ;;
    2)
        ENV_TYPE="prod"
        ;;
    *)
        echo "錯誤：無效的選項（必須是 1 或 2）"
        exit 1
        ;;
esac

# 顯示確認資訊
echo "
即將生成以下配置的 Nginx 設定：
- 專案名稱：$PROJECT_NAME
- 域名：$NGINX_HOST
- 環境類型：$ENV_TYPE
"
read -p "確認繼續？(y/n): " confirm
if [ "$confirm" != "y" ]; then
    echo "已取消操作"
    exit 0
fi

NGINX_CONF_DIR="nginx/conf.d"
TEMPLATE_PATH="$NGINX_CONF_DIR"

# 根據環境類型選擇模板
case $ENV_TYPE in
    dev)
        TEMPLATE_PATH="$NGINX_CONF_DIR/dev.conf.template"
        ;;
    prod)
        TEMPLATE_PATH="$NGINX_CONF_DIR/prod.conf.template"
        ;;
    *)
        echo "錯誤：無效的環境類型 $ENV_TYPE（必須是 dev 或 prod）"
        exit 1
        ;;
esac

# 檢查模板文件是否存在
if [ ! -f "$TEMPLATE_PATH" ]; then
    echo "錯誤：找不到模板文件 $TEMPLATE_PATH"
    exit 1
fi

# 生成配置文件
echo "正在生成 Nginx 配置..."
PROJECT_NAME="$PROJECT_NAME" NGINX_HOST="$NGINX_HOST" envsubst '${NGINX_HOST} ${PROJECT_NAME}' < "$TEMPLATE_PATH" > "$NGINX_CONF_DIR/default.conf"

echo "Nginx 配置生成成功！"
echo "- 專案名稱：$PROJECT_NAME"
echo "- 域名：$NGINX_HOST"
echo "- 環境：$ENV_TYPE"