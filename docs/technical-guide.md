# SrLWordpress 技術指南

本文檔提供 SrLWordpress 專案的技術細節，包括配置說明、優化建議和故障排除指南。

## Nginx 配置管理

### 配置文件結構

```
nginx/
├── conf.d/
│   ├── default.conf        # 動態生成的配置文件
│   ├── dev.conf.template   # 開發環境模板
│   └── prod.conf.template  # 生產環境模板
└── certs/                  # SSL 證書目錄
    └── .gitkeep
```

### 配置生成流程

1. **環境變數設定**
```ini
# .env 文件中的必要變數
PROJECT_NAME=your_project    # 用於 SSL 證書命名
NGINX_HOST=your-domain      # 網站域名
ENV_TYPE=dev|prod          # 環境類型
```

2. **配置生成腳本**
```bash
# scripts/generate-nginx-conf.sh
# 根據環境變數選擇適當的模板並生成配置
```

3. **自動化處理**
```yaml
# docker-compose.yml 中的 Nginx 服務配置
nginx:
  volumes:
    - ./nginx/conf.d:/etc/nginx/conf.d
    - ./scripts:/scripts
  environment:
    - PROJECT_NAME=${PROJECT_NAME}
    - NGINX_HOST=${NGINX_HOST}
    - ENV_TYPE=${ENV_TYPE:-dev}
  command: >
    /bin/sh -c "
    chmod +x /scripts/generate-nginx-conf.sh &&
    /scripts/generate-nginx-conf.sh &&
    nginx -g 'daemon off;'"
```

### 配置模板說明

#### 開發環境模板 (dev.conf.template)

```nginx
server {
    listen 80;
    server_name ${NGINX_HOST};
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl http2;
    server_name ${NGINX_HOST};
    
    # SSL 配置
    ssl_certificate /etc/nginx/certs/dev_${PROJECT_NAME}.crt;
    ssl_certificate_key /etc/nginx/certs/dev_${PROJECT_NAME}.key;
    
    # 開發環境特定配置
    fastcgi_read_timeout 300;
    client_max_body_size 64M;
    
    # ... 其他配置
}
```

#### 生產環境模板 (prod.conf.template)

```nginx
server {
    listen 443 ssl http2;
    server_name ${NGINX_HOST};
    
    # SSL 配置
    ssl_certificate /etc/nginx/certs/prod_${PROJECT_NAME}.crt;
    ssl_certificate_key /etc/nginx/certs/prod_${PROJECT_NAME}.key;
    
    # 生產環境安全配置
    add_header Content-Security-Policy "default-src 'self'";
    
    # ... 其他配置
}
```

### 配置驗證

```bash
# 檢查生成的配置
docker-compose exec nginx cat /etc/nginx/conf.d/default.conf

# 驗證配置語法
docker-compose exec nginx nginx -t

# 重新載入配置
docker-compose exec nginx nginx -s reload
```

### 故障排除

1. **配置生成失敗**
   - 檢查環境變數是否正確設定
   - 確認模板文件存在
   - 檢查腳本執行權限

2. **SSL 證書問題**
   - 確認證書文件存在且命名正確
   - 檢查證書權限
   - 驗證證書路徑

3. **域名解析問題**
   - 確認 hosts 文件設定（開發環境）
   - 檢查 DNS 記錄（生產環境）

## PHP 配置

### PHP-FPM 設定

```ini
memory_limit = 256M
max_execution_time = 120
upload_max_filesize = 32M
post_max_size = 32M
```

### OPcache 配置

```ini
opcache.enable = 1
opcache.memory_consumption = 128
opcache.max_accelerated_files = 4000
```

## Redis 配置

### 基本設定

```yaml
redis:
    mem_limit: 128m
    mem_reservation: 64m
    command: redis-server --maxmemory 100mb --maxmemory-policy allkeys-lru
```

### WordPress 整合

```php
define('WP_REDIS_HOST', 'redis');
define('WP_CACHE', true);
```

## 資源限制

### 容器限制

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
```

### 系統優化

```bash
# /etc/sysctl.conf
vm.swappiness = 10
vm.vfs_cache_pressure = 50
```

## 監控和日誌

### 日誌配置

```nginx
# Nginx 日誌
access_log /var/log/nginx/access.log;
error_log /var/log/nginx/error.log;

# PHP 日誌
php_admin_value[error_log] = /var/log/php-fpm.log;
```

### 監控命令

```bash
# 容器狀態
docker stats

# 日誌查看
docker-compose logs -f [service]

# 資源使用
htop
```

## 備份策略

### 自動備份

```bash
# 設定定時備份
0 3 * * * cd /var/www/products/[repository_name] && ./scripts/backup.sh
```

### 手動備份

```bash
./scripts/export-data.sh
```

## 安全性

### 文件權限

```bash
find wp -type d -exec chmod 755 {} \;
find wp -type f -exec chmod 644 {} \;
```

### SSL/TLS 配置

```nginx
ssl_protocols TLSv1.2 TLSv1.3;
ssl_prefer_server_ciphers off;
ssl_session_tickets off;
```

## 性能優化

### Nginx 快取

```nginx
fastcgi_cache_path /tmp/nginx-cache levels=1:2 keys_zone=WORDPRESS:100m;
fastcgi_cache_key "$scheme$request_method$host$request_uri";
```

### 資料庫優化

```ini
innodb_buffer_pool_size = 128M
max_connections = 50
```

## 開發工具

### WP-CLI

```bash
docker-compose exec wordpress wp --info
```

### 除錯工具

```php
define('WP_DEBUG', true);
define('WP_DEBUG_LOG', true);
