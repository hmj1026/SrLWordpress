# SSL 證書設定指南

本文檔說明如何在不同環境中管理 SSL 證書。

## 證書命名規則

證書檔案採用以下命名格式：
- 開發環境：dev_{project_name}.crt/key
- 生產環境：prod_{project_name}.crt/key

例如，專案名稱為 "mysite" 時：
- 開發環境：dev_mysite.crt 和 dev_mysite.key
- 生產環境：prod_mysite.crt 和 prod_mysite.key

## 開發環境設定

### 1. 設定環境變數

編輯 `.env` 文件：
```ini
PROJECT_NAME=mysite          # 專案名稱
NGINX_HOST=mysite.dev       # 開發域名
ENV_TYPE=dev               # 環境類型
```

### 2. 生成自簽證書

```bash
# 設定腳本權限
chmod +x scripts/generate-ssl.sh

# 執行生成腳本
./scripts/generate-ssl.sh
```

腳本會自動完成以下操作：
1. 在 nginx/certs 目錄生成 dev_mysite.key 和 dev_mysite.crt
2. 自動配置本地 hosts 文件（需 sudo 權限）
3. 重啟 Nginx 容器

### 3. 驗證配置

```bash
docker-compose exec nginx nginx -t
```

## 生產環境設定

### 1. 設定環境變數

編輯 `.env` 文件：
```ini
PROJECT_NAME=mysite          # 專案名稱
NGINX_HOST=mysite.com       # 正式域名
ENV_TYPE=prod              # 環境類型
```

### 2. 使用 Let's Encrypt

```bash
# 停止 Nginx 服務
docker-compose stop nginx

# 使用 certbot 獲取證書（需開放 80/443 端口）
sudo certbot certonly --standalone -d mysite.com

# 複製證書到指定位置
sudo cp /etc/letsencrypt/live/mysite.com/{fullchain.pem,privkey.pem} nginx/certs/prod_mysite.{crt,key}

# 重啟服務
docker-compose up -d
```

## 混合環境配置

多域名範例：
```ini
NGINX_HOST=dev.mysite.com,prod.mysite.com
```

對應證書命名：
- 開發：dev_mysite.crt/key
- 生產：prod_mysite.crt/key

## 注意事項

1. 證書有效期監控：
```bash
openssl x509 -in nginx/certs/${ENV_TYPE}_${PROJECT_NAME}.crt -noout -dates
```

2. 自動續期設定（生產環境）：
```bash
# 每月 1 號凌晨 2:30 自動續期
30 2 1 * * root certbot renew --quiet --deploy-hook "docker-compose restart nginx"
```

3. 開發環境證書需手動加入系統信任庫：
```bash
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain nginx/certs/dev_mysite.crt
```

4. 證書目錄結構：
```
nginx/
└── certs/
    ├── dev_mysite.crt
    ├── dev_mysite.key
    ├── prod_mysite.crt
    └── prod_mysite.key
