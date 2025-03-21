# Linode 生產環境部署指南

## 前置準備

1. Linode 帳號和 API Token
2. 已完成本地環境測試
3. 已準備好正式網站的備份資料
4. 已購買網域並可以管理 DNS 設定

## 部署步驟

### 1. Linode 實例設定

1. 登入 Linode Cloud Manager
2. 建立新的 Linode：
   - **方案選擇**：Nanode 1GB
     * CPU: 1 核心
     * RAM: 1GB
     * Storage: 25GB
     * Transfer: 1TB
   - **地區**：選擇離目標用戶最近的數據中心（建議：Tokyo 2）
   - **映像**：Ubuntu 24.04 LTS
   - **標籤**：production

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

# 如果使用 docker-compose up，配置會自動生成
# 手動生成配置（如果需要）：
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

### 10. 備份策略

```bash
# 建立備份目錄
mkdir -p backups

# 設定定時備份
echo "0 3 * * * cd /var/www/products/[repository_name] && ./scripts/backup.sh" | crontab -

# 設定備份保留期限（7天）
find backups -type d -mtime +7 -exec rm -rf {} +
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

## 安全建議

1. 定期更新系統和套件
2. 監控異常訪問
3. 定期檢查日誌
4. 維護備份
5. 限制管理員訪問

## 性能優化

1. 定期清理快取
2. 優化資料庫查詢
3. 監控資源使用
4. 調整容器限制
5. 優化 Nginx 配置
