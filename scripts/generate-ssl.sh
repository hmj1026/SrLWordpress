#!/bin/bash

# 設定變數
CERTS_DIR="nginx/certs"
DAYS_VALID=3650  # 10年有效期

# 確保證書目錄存在
mkdir -p $CERTS_DIR

# 詢問專案名稱
read -p "請輸入專案名稱: " PROJECT_NAME
if [ -z "$PROJECT_NAME" ]; then
    echo "錯誤：專案名稱不能為空"
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
        DEFAULT_DOMAIN="develop.dev"
        ;;
    2)
        ENV_TYPE="prod"
        DEFAULT_DOMAIN="production.prod"
        ;;
    *)
        echo "無效的選項"
        exit 1
        ;;
esac

# 詢問域名
read -p "請輸入域名: " DOMAIN
if [ -z "$DOMAIN" ]; then
    echo "錯誤：域名不能為空"
    exit 1
fi

# 確認設定
echo "
即將生成以下配置的 SSL 證書：
環境類型: $ENV_TYPE
域名: $DOMAIN
證書有效期: $DAYS_VALID 天
"
read -p "確認繼續？(y/n): " confirm
if [ "$confirm" != "y" ]; then
    echo "已取消操作"
    exit 0
fi

# 生成證書
generate_cert() {
    local domain=$1
    local env_type=$2
    
    echo "生成 $domain 的 SSL 證書..."
    
    # 生成 private key
    openssl genrsa -out "$CERTS_DIR/${ENV_TYPE}_${PROJECT_NAME}.key" 2048
    
    # 生成 CSR 配置
    cat > "$CERTS_DIR/${ENV_TYPE}_${PROJECT_NAME}.conf" << EOF
[req]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn
x509_extensions = v3_req

[dn]
C = TW
ST = Taiwan
L = Taipei
O = Linstar Development
OU = IT Department
CN = $domain

[v3_req]
subjectAltName = @alt_names
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment

[alt_names]
DNS.1 = $domain
DNS.2 = *.$domain
EOF
    
    # 生成 CSR
    openssl req -new \
        -key "$CERTS_DIR/${ENV_TYPE}_${PROJECT_NAME}.key" \
        -out "$CERTS_DIR/${ENV_TYPE}_${PROJECT_NAME}.csr" \
        -config "$CERTS_DIR/${ENV_TYPE}_${PROJECT_NAME}.conf"
    
    # 生成自簽證書
    openssl x509 -req \
        -days $DAYS_VALID \
        -in "$CERTS_DIR/${ENV_TYPE}_${PROJECT_NAME}.csr" \
        -signkey "$CERTS_DIR/${ENV_TYPE}_${PROJECT_NAME}.key" \
        -out "$CERTS_DIR/${ENV_TYPE}_${PROJECT_NAME}.crt" \
        -extensions v3_req \
        -extfile "$CERTS_DIR/${ENV_TYPE}_${PROJECT_NAME}.conf"
    
    # 清理臨時文件
    rm "$CERTS_DIR/${ENV_TYPE}_${PROJECT_NAME}.csr" "$CERTS_DIR/${ENV_TYPE}_${PROJECT_NAME}.conf"
    
    echo "$domain 的 SSL 證書生成完成"
}

# 生成證書
generate_cert $DOMAIN $ENV_TYPE

echo "
證書生成完成！

證書文件位置：
- Private Key: $CERTS_DIR/${ENV_TYPE}_${PROJECT_NAME}.key
- Certificate: $CERTS_DIR/${ENV_TYPE}_${PROJECT_NAME}.crt
"

if [ "$ENV_TYPE" = "dev" ]; then
    echo "請將以下內容加入到您的 hosts 文件（/etc/hosts）：
127.0.0.1 $DOMAIN

注意：這是開發環境的自簽證書，僅供測試使用。"
else
    echo "注意：在生產環境中建議使用 Let's Encrypt 等受信任的證書。"
fi

# 設定權限
chmod 600 $CERTS_DIR/*.key
