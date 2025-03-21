#!/bin/bash

# 檢查必要的環境變數
if [ -z "$PROJECT_NAME" ]; then
    echo "錯誤：未設定 PROJECT_NAME 環境變數"
    exit 1
fi

if [ -z "$NGINX_HOST" ]; then
    echo "錯誤：未設定 NGINX_HOST 環境變數"
    exit 1
fi

if [ -z "$ENV_TYPE" ]; then
    echo "錯誤：未設定 ENV_TYPE 環境變數"
    exit 1
fi

NGINX_CONF_DIR="/etc/nginx/conf.d"
TEMPLATE_PATH=""

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
envsubst '${NGINX_HOST} ${PROJECT_NAME}' < "$TEMPLATE_PATH" > "$NGINX_CONF_DIR/default.conf"

# 驗證配置
echo "驗證 Nginx 配置..."
nginx -t

if [ $? -eq 0 ]; then
    echo "Nginx 配置生成成功！"
    echo "- 專案名稱：$PROJECT_NAME"
    echo "- 域名：$NGINX_HOST"
    echo "- 環境：$ENV_TYPE"
else
    echo "錯誤：Nginx 配置驗證失敗"
    exit 1
fi
