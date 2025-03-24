# Linode 生產環境部署指南

## 前置準備

1.  Linode 帳號和 API Token
2.  已完成本地環境測試
3.  已準備好正式網站的備份資料
4.  已購買網域並可以管理 DNS 設定

## 部署步驟

### 1. Linode 實例設定

1.  登入 Linode Cloud Manager
2.  建立新的 Linode：
    *   **方案選擇**：Nanode 1GB
        *   CPU: 1 核心
        *   RAM: 1GB
        *   Storage: 25GB
        *   Transfer: 1TB
    *   **地區**：選擇離目標用戶最近的數據中心（建議：Tokyo 2）
    *   **映像**：Ubuntu 24.04 LTS
    *   **標籤**：production

### 2. 基礎系統設定

```bash
# 系統更新
apt update && apt upgrade -y

# 安裝必要工具
apt install -y docker.io docker-compose git certbot

# 建立 swap 空間（對 1GB RAM 很重要）
fallocate -l 2G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab

# 系統參數優化（針對 1GB RAM）
cat >> /etc/sysctl.conf << EOF
# 記憶體優化
vm.swappiness = 10
vm.vfs_cache_pressure = 50

# 網絡優化（低記憶體配置）
net.core.somaxconn = 1024
net.ipv4.tcp_max_tw_buckets = 4096
net.ipv4.tcp_max_syn_backlog = 2048
net.core.netdev_max_backlog = 1000

# 文件系統優化
fs.file-max = 65536
fs.inotify.max_user_watches = 32768
EOF

sysctl -p
```

### 3. 安全性設定

```bash
# 設定防火牆
apt install -y ufw fail2ban
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow http
ufw allow https
ufw enable

# 配置 Fail2ban（輕量配置）
cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
cat >> /etc/fail2ban/jail.local << EOF
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 3
EOF

systemctl restart fail2ban
```

### 4. 專案部署

```bash
# 建立專案目錄
mkdir -p /var/www/products
cd /var/www/products

# Clone 專案到指定目錄
git clone [your-repo-url] [repository_name]
cd [repository_name]

# 設定環境變數
cp .env.example .env

# 編輯 .env 文件，設定：
# 基本設定
PROJECT_NAME=your_project
NGINX_HOST=your-domain.com
ENV_TYPE=prod

# 資料庫和 PHP 設定
PHP_MEMORY_LIMIT=256M
MAX_EXECUTION_TIME=120
UPLOAD_MAX_FILESIZE=32M
POST_MAX_SIZE=32M
MYSQL_MAX_CONNECTIONS=50
```

### 5. Nginx 配置設定

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

# 手動生成配置
docker-compose exec nginx /scripts/generate-nginx-conf.sh

# 驗證生成的配置
docker-compose exec nginx cat /etc/nginx/conf.d/default.conf
docker-compose exec nginx nginx -t
```

### 6. SSL 證書設定

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

### 7. Docker 配置優化

編輯 docker-compose.yml，加入資源限制：

```yaml
services:
  wordpress:
    mem_limit: 300m
    mem_reservation: 200m

  mysql:
    mem_limit: 300m
    mem_reservation: 200m

  nginx:
    mem_limit: 128m
    mem_reservation: 64m

  redis:
    mem_limit: 128m
    mem_reservation: 64m
    command: redis-server --maxmemory 100mb --maxmemory-policy allkeys-lru
```

### 8. 啟動服務

```bash
# 構建並啟動所有容器
# 這會自動執行 generate-nginx-conf.sh
docker-compose up -d

# 確認所有容器都正常運行
docker-compose ps

# 檢查 Nginx 配置和狀態
docker-compose exec nginx nginx -t
curl -I https://${NGINX_HOST}
```

### 9. 性能監控設定

```bash
# 安裝基本監控工具
apt install -y htop

# 安裝 netdata
wget -O /tmp/netdata-kickstart.sh https://get.netdata.cloud/kickstart.sh
sh /tmp/netdata-kickstart.sh --non-interactive

# 配置 netdata（輕量級設定）
sed -i 's/# memory mode = save/memory mode = ram/g' /etc/netdata/netdata.conf
systemctl restart netdata
```

## 維護指南

### 1. 定期維護

```bash
# 系統更新
apt update && apt upgrade -y

# 容器更新
docker-compose pull
docker-compose up -d

# WordPress 更新
docker-compose exec wordpress wp core update
docker-compose exec wordpress wp plugin update --all
docker-compose exec wordpress wp theme update --all
```

### 2. 日誌管理

```bash
# 設定日誌輪替
cat > /etc/logrotate.d/docker-wordpress << EOF
/var/lib/docker/containers/*/*.log {
    rotate 7
    daily
    compress
    size=10M
    missingok
    delaycompress
    copytruncate
}
EOF
```

### 3. SSL 證書維護

```bash
# 手動更新證書
certbot renew
docker-compose restart nginx

# 檢查證書狀態
certbot certificates
```

#### 使用 Certbot 的 Standalone 模式自動更新憑證

1.  **建立排程任務 (crontab)**：

```bash
  # 編輯 crontab 設定
  crontab -e
```

2.  **添加以下排程任務**：

```
  0 0 1 * * /usr/bin/docker stop wp_nginx && /usr/bin/certbot renew --quiet --standalone && /usr/bin/docker start wp_nginx && /bin/cp /etc/letsencrypt/live/your-domain.com/fullchain.pem /var/www/products/[repository_name]/nginx/certs/prod_${PROJECT_NAME}.crt && /bin/cp /etc/letsencrypt/live/your-domain.com/privkey.pem /var/www/products/[repository_name]/nginx/certs/prod_${PROJECT_NAME}.key && /usr/bin/docker exec wp_nginx nginx -s reload
```

3.  **保存並關閉文件**。

**排程任務說明**：

*   `0 0 1 * *`：表示在每個月的第 1 天的凌晨 0 點 0 分執行。
*   `/usr/bin/docker stop wp_nginx`：停止 Nginx 容器。
*   `/usr/bin/certbot renew --quiet --standalone`：使用 Certbot 的 standalone 模式更新證書，`--quiet` 選項表示靜默模式，不輸出詳細信息。
*   `/usr/bin/docker start wp_nginx`：啟動 Nginx 容器。
*   `/bin/cp /etc/letsencrypt/live/your-domain.com/fullchain.pem ...`：將更新後的證書文件複製到項目目錄中。
*   `/bin/cp /etc/letsencrypt/live/your-domain.com/privkey.pem ...`：將更新後的私鑰文件複製到項目目錄中。
*   `/usr/bin/docker exec wp_nginx nginx -s reload`：在 Nginx 容器中重新加載 Nginx 配置。

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

### 2. 容器問題

```bash
# 查看容器狀態
docker-compose ps

# 查看容器日誌
docker-compose logs -f [service_name]

# 重啟特定服務
docker-compose restart [service_name]
```

### 3. 資源問題

```bash
# 檢查資源使用
docker stats

# 清理系統
docker system prune
```

### 4. Docker 服務和容器問題

如果遇到與 Docker 相關的錯誤，例如無法啟動容器、無法執行 `docker-compose` 命令等，請嘗試以下步驟：

#### 方法 1：檢查 Docker 服務狀態

```bash
# 檢查 Docker 服務是否正在運行（可能需要 sudo）
systemctl status docker

# 如果 Docker 服務未運行，嘗試啟動它
systemctl start docker

# 檢查 Docker 服務是否已啟用（開機自啟動）
systemctl is-enabled docker

# 如果未啟用，啟用 Docker 服務
systemctl enable docker
```

#### 方法 2：重啟 Docker 服務

```bash
# 重啟 Docker 服務（可能需要 sudo）
systemctl restart docker
```

#### 方法 3：重建 Docker 容器

```bash
# 停止並刪除所有容器
docker-compose down

# 重新構建並啟動容器
docker-compose up --build -d
```

#### 方法 4：檢查 Docker Compose 版本

```bash
# 檢查 Docker Compose 版本
docker-compose --version

# 如果版本過舊，嘗試更新 Docker Compose
# （請參考 Docker Compose 官方文檔獲取最新安裝說明）
```

#### 方法 5：檢查系統日誌

```bash
# 查看系統日誌，查找與 Docker 相關的錯誤信息
journalctl -u docker.service

# 查看更詳細的日誌（可能需要 sudo）
journalctl -xe
```

### 5. WordPress 文件缺失問題

如果您發現 wp 目錄是空的，或者在瀏覽器中訪問網站時遇到 403 Forbidden 錯誤，並在 Nginx 日誌中看到類似以下內容：

```
[error] *1 directory index of "/var/www/html/" is forbidden, client: x.x.x.x, server: your-domain.com, request: "GET / HTTP/2.0", host: "your-domain.com"
```

這通常表示 WordPress 文件未正確安裝。解決方法：

#### 方法 1：檢查 WordPress 文件

```bash
# 檢查 wp 目錄是否為空
ls -la wp/

# 檢查 WordPress 容器中的文件
docker-compose exec wordpress ls -la /var/www/html/

# 如果目錄為空，需要安裝 WordPress
```

#### 方法 2：手動下載 WordPress 文件

```bash
# 進入專案目錄
cd /var/www/products/[repository_name]

# 下載最新版 WordPress
wget https://wordpress.org/latest.tar.gz

# 解壓縮到 wp 目錄
tar -xzf latest.tar.gz
cp -a wordpress/. wp/
rm -rf wordpress latest.tar.gz

# 設置正確的權限
chown -R www-data:www-data wp/
find wp/ -type d -exec chmod 755 {} \;
find wp/ -type f -exec chmod 644 {} \;

# 重啟容器
docker-compose restart
```

#### 方法 3：使用 WP-CLI 安裝 WordPress

```bash
# 確保 wp 目錄存在
mkdir -p wp

# 使用 WP-CLI 下載 WordPress 核心文件
docker-compose exec wordpress wp core download --path=/var/www/html --force

# 創建 wp-config.php 文件
docker-compose exec wordpress wp config create \
  --dbname=${MYSQL_DATABASE} \
  --dbuser=${MYSQL_USER} \
  --dbpass=${MYSQL_PASSWORD} \
  --dbhost=mariadb \
  --path=/var/www/html

# 安裝 WordPress
docker-compose exec wordpress wp core install \
  --url=${NGINX_HOST} \
  --title="WordPress Site" \
  --admin_user=admin \
  --admin_password=your_password \
  --admin_email=your_email@example.com \
  --path=/var/www/html

# 設置正確的權限
docker-compose exec wordpress chown -R www-data:www-data /var/www/html
```

#### 方法 4：檢查 docker-compose.yml 中的卷配置

確保 docker-compose.yml 文件中正確配置了卷映射：

```yaml
services:
  wordpress:
    volumes:
      - ./wp:/var/www/html
```

如果配置正確但 wp 目錄仍然為空，可能是權限問題或容器未正確掛載卷。嘗試重新創建容器：

```bash
docker-compose down
docker-compose up -d
```

### 6. Nginx 403 Forbidden 錯誤

如果 WordPress 文件已正確安裝但仍然遇到 403 Forbidden 錯誤，可能是 Nginx 配置問題：

#### 方法 1：檢查目錄權限

```bash
# 設置正確的目錄權限
docker-compose exec wordpress chown -R www-data:www-data /var/www/html/
docker-compose exec wordpress find /var/www/html/ -type d -exec chmod 755 {} \;
docker-compose exec wordpress find /var/www/html/ -type f -exec chmod 644 {} \;
```

#### 方法 2：檢查 Nginx 配置

```bash
# 檢查 Nginx 配置中的 root 路徑
docker-compose exec nginx cat /etc/nginx/conf.d/default.conf | grep root

# 確保 try_files 指令正確
docker-compose exec nginx cat /etc/nginx/conf.d/default.conf | grep -A 5 "location /"

# 修改 Nginx 配置，確保 index 指令包含 index.php
cat > nginx/conf.d/default.conf << EOF
server {
    listen 80;
    server_name ${NGINX_HOST};
    
    root /var/www/html;
    index index.php index.html index.htm;

    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    location ~ \.php$ {
        fastcgi_pass wordpress:9000;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param PATH_INFO \$fastcgi_path_info;
    }
}
EOF

# 重啟 Nginx
docker-compose restart nginx
```

#### 方法 3：檢查 WordPress 是否正確安裝

```bash
# 檢查 WordPress 是否已安裝
docker-compose exec wordpress wp core is-installed

# 如果未安裝，可以運行安裝
docker-compose exec wordpress wp core install \
  --url=${NGINX_HOST} \
  --title="WordPress Site" \
  --admin_user=admin \
  --admin_password=your_password \
  --admin_email=your_email@example.com
```
### 7. 備份問題

如果執行 `./scripts/export-data.sh` 腳本備份資料庫時遇到問題，請嘗試以下故障排除步驟：

#### 方法 1：檢查資料庫憑證

確保 `.env` 文件中的資料庫憑證（`MYSQL_USER`、`MYSQL_PASSWORD`、`MYSQL_DATABASE`）與 MariaDB 容器中的實際憑證相符。

#### 方法 2：檢查 MariaDB 容器狀態

使用 `docker-compose ps` 命令檢查 MariaDB 容器（`wp_db`）是否正在運行。如果容器未運行，請嘗試重新啟動容器：

```bash
docker-compose restart mariadb
```

#### 方法 3：檢查 mysqldump 命令

嘗試在容器內部手動執行 `mysqldump` 命令，以獲取更詳細的錯誤訊息：

```bash
docker exec wp_db mysqldump -u${MYSQL_USER} -p${MYSQL_PASSWORD} ${MYSQL_DATABASE}
```

如果命令執行失敗，請檢查錯誤訊息，並根據錯誤訊息進行故障排除。

#### 方法 4： 檢查資料庫是否存在
使用以下指令進入mysql
```
docker exec -it wp_db mysql -u${MYSQL_USER} -p${MYSQL_PASSWORD}
```
然後
```
show databases;
```
檢查是否有${MYSQL_DATABASE}