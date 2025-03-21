# 生產環境部署指南

## 前置準備

1. 已取得生產環境伺服器存取權限
2. 已設定好網域的 DNS 記錄
3. 已準備好要部署的資料（使用 export-data.sh 產生的備份）
4. 已完成本地開發環境測試（參考 local-dev-setup.md）

## 部署步驟

### 1. 伺服器環境準備

```bash
# 更新系統套件
apt update && apt upgrade -y

# 安裝必要工具
apt install -y docker.io docker-compose git certbot

# 啟動並啟用服務
systemctl start docker
systemctl enable docker
```

### 2. 安全性設定

```bash
# 設定防火牆
ufw allow ssh
ufw allow http
ufw allow https
ufw enable

# 設定 SSH 安全性（編輯 /etc/ssh/sshd_config）
- 禁用密碼登入
- 限制 root 登入
- 更改預設 SSH 端口（選擇性）
```

### 3. 專案部署

```bash
# 建立專案目錄
mkdir -p /var/www/products
cd /var/www/products

# 取得專案程式碼
git clone [your-repo-url] [repository_name]
cd [repository_name]

# 設定環境變數
cp .env.example .env

# 編輯 .env 文件，設定：
# 基本設定
PROJECT_NAME=your_project    # 專案名稱
NGINX_HOST=your-domain.com  # 生產域名
ENV_TYPE=prod              # 環境類型

# 資料庫和 PHP 設定
PHP_MEMORY_LIMIT=256M
MAX_EXECUTION_TIME=120
UPLOAD_MAX_FILESIZE=32M
POST_MAX_SIZE=32M
MYSQL_MAX_CONNECTIONS=50
```

### 4. Nginx 配置設定

```bash
# 確認配置模板存在
ls nginx/conf.d/prod.conf.template

# 設定腳本執行權限
chmod +x scripts/generate-nginx-conf.sh

# 檢查環境變數
echo "檢查環境變數設定："
echo "PROJECT_NAME=${PROJECT_NAME}"
echo "NGINX_HOST=${NGINX_HOST}"
echo "ENV_TYPE=${ENV_TYPE}"

# 配置會在容器啟動時自動生成
```

### 5. SSL 證書設定

```bash
# 安裝 Certbot
apt install -y certbot python3-certbot-nginx

# 申請 Let's Encrypt 證書
certbot certonly --webroot \
  -w /var/www/products/[repository_name]/public \
  -d your-domain.com

# 複製並重命名證書
cp /etc/letsencrypt/live/your-domain.com/fullchain.pem nginx/certs/prod_${PROJECT_NAME}.crt
cp /etc/letsencrypt/live/your-domain.com/privkey.pem nginx/certs/prod_${PROJECT_NAME}.key

# 設定自動更新
echo "0 0 1 * * certbot renew --quiet && docker-compose restart nginx" | crontab -
```

### 6. 資料部署

```bash
# 建立備份目錄
mkdir -p backups

# 上傳備份文件
scp backups/database_*.sql user@your-server:/var/www/products/[repository_name]/backups/
scp backups/wp_backup_*.tar.gz user@your-server:/var/www/products/[repository_name]/backups/

# 匯入資料
chmod +x scripts/import-data.sh
./scripts/import-data.sh backups/database_*.sql backups/wp_backup_*.tar.gz

# 設定檔案權限
chown -R www-data:www-data wp
find wp -type d -exec chmod 755 {} \;
find wp -type f -exec chmod 644 {} \;
```

### 7. 啟動服務

```bash
# 構建並啟動容器
# 這會自動執行 generate-nginx-conf.sh
docker-compose up -d --build

# 驗證服務狀態
docker-compose ps
docker-compose logs

# 檢查 Nginx 配置
docker-compose exec nginx nginx -t
docker-compose exec nginx cat /etc/nginx/conf.d/default.conf

# 檢查網站可訪問性
curl -I https://your-domain.com
```

### 8. 最終確認

1. 訪問網站前台確認正常運作
2. 登入後台檢查設定
3. 確認 SSL 證書正確安裝
4. 驗證資料庫連接
5. 測試 Redis 快取功能
6. 檢查檔案權限
7. 確認備份功能正常運作

## 維護計劃

### 1. 自動備份設定

```bash
# 每日備份
echo "0 2 * * * cd /var/www/products/[repository_name] && ./scripts/export-data.sh" | crontab -

# 設定備份保留期限（7天）
find /var/www/products/[repository_name]/backups -type d -mtime +7 -exec rm -rf {} +
```

### 2. 監控設定

```bash
# 設定容器監控
docker stats

# 設定日誌輪替
cat > /etc/logrotate.d/wordpress << EOF
/var/www/products/[repository_name]/logs/*.log {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
    create 0640 www-data www-data
}
EOF
```

### 3. 安全更新

```bash
# 系統更新
apt update && apt upgrade -y

# WordPress 核心更新
docker-compose exec wordpress wp core update

# 外掛更新
docker-compose exec wordpress wp plugin update --all

# 主題更新
docker-compose exec wordpress wp theme update --all
```

## 故障排除

### 1. Nginx 相關問題

```bash
# 檢查配置
docker-compose exec nginx nginx -t

# 查看錯誤日誌
docker-compose exec nginx tail -f /var/log/nginx/error.log

# 重新生成配置
docker-compose exec nginx /scripts/generate-nginx-conf.sh
```

### 2. SSL 證書問題

```bash
# 檢查證書狀態
certbot certificates

# 手動更新證書
certbot renew
docker-compose restart nginx

# 檢查證書路徑
ls -l nginx/certs/prod_${PROJECT_NAME}.*
```

### 3. 容器問題

```bash
# 查看容器狀態
docker-compose ps

# 查看容器日誌
docker-compose logs -f [service_name]

# 重啟特定服務
docker-compose restart [service_name]
```

### 4. 資料庫問題

```bash
# 檢查資料庫連接
docker-compose exec wordpress wp db check

# 檢查資料庫日誌
docker-compose logs mariadb
```

### 5. 權限問題

```bash
# 修復 WordPress 文件權限
docker-compose exec wordpress chown -R www-data:www-data /var/www/html
```

### 回滾部署

如果需要回滾到之前的版本：

1. 停止服務
```bash
docker-compose down
```

2. 還原備份
```bash
./scripts/import-data.sh backups/database_[old-version].sql backups/wp_backup_[old-version].tar.gz
```

3. 重啟服務
```bash
docker-compose up -d
```

## 性能優化

1. 定期清理：
   - Docker 系統：`docker system prune`
   - 日誌文件：`logrotate`
   - 資料庫優化：`wp db optimize`

2. 監控資源使用：
   - 容器統計：`docker stats`
   - 系統資源：`htop`
   - 磁碟使用：`df -h`

3. 配置優化：
   - Nginx 快取
   - PHP OPcache
   - MySQL 查詢快取
   - Redis 物件快取
