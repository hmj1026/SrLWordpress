# SrLWordpress 技術指南

本文檔提供 SrLWordpress 專案的技術細節，包括配置說明、優化建議和故障排除指南。

## 環境配置

### PHP 配置

SrLWordpress 使用基於 PHP 8.2 FPM 的自定義映像，通過 `php.ini` 優化 WordPress 性能。主要配置項包括：

```ini
memory_limit = 256M
upload_max_filesize = 64M
post_max_size = 64M
max_execution_time = 300
max_input_time = 300
opcache.enable = 1
opcache.memory_consumption = 128
opcache.max_accelerated_files = 4000
```

這些設置允許處理較大的上傳文件和複雜的 WordPress 操作。

### Nginx 配置

Nginx 配置(`nginx/conf.d/default.conf`)包含以下關鍵功能：

1. 靜態文件緩存
2. FastCGI 參數優化
3. WordPress 永久連接支持

關鍵配置：

```nginx
location / {
    try_files $uri $uri/ /index.php?$args;
}

location ~ \.php$ {
    fastcgi_pass wordpress:9000;
    fastcgi_buffers 16 16k;
    fastcgi_buffer_size 32k;
}

location ~* \.(js|css|png|jpg|jpeg|gif|ico)$ {
    expires max;
    log_not_found off;
}
```

### Redis 對象緩存

WordPress 使用 Redis 進行對象緩存，通過在 `wp-config.php` 中添加以下設置：

```php
define('WP_REDIS_HOST', 'redis');
define('WP_CACHE', true);
```
需確保 Redis 容器正常運行，並安裝相應的 WordPress Redis 插件（如「Redis Object Cache」）

## 性能優化

### 資料庫優化

MariaDB 配置基於 WordPress 最佳實踐。如需進一步優化，可以修改 `my.cnf` 配置文件（需要額外創建）。

### 緩存策略

SrLWordpress 採用多層緩存：

1. Redis 對象緩存: 減少資料庫查詢
2. Nginx 靜態文件緩存: 加速資源加載
3. PHP OPcache: 提升 PHP 執行效率

### 高可用性配置

對於生產環境，建議考慮以下增強：

1. 使用 Docker Swarm 或 Kubernetes 進行容器編排
2. 實施資料庫複制
3. 添加 CDN 支持

## 開發工作流

### 本地開發

1. 修改主題或插件：直接編輯 `./wp` 目錄中的文件，容器會自動同步
2. 使用 WP-CLI 進行 WordPress 管理任務 
    - 執行 `docker-compose exec wordpress wp <command>`
    - 重啟服務：`docker-compose restat wordpress`
3. Docker 容器自動同步文件變更


### 調試

1. 啟用 PHP 錯誤日誌：修改 `php.ini` 中的 `display_errors = On`
2. 查看 Docker 日誌：`docker-compose logs -f`
3. 使用 WP_DEBUG：在 WordPress 配置中添加 `define('WP_DEBUG', true);`

## 故障排除

### 常見問題

1. **無法連接到資料庫**
   - 檢查 `.env` 設置
   - 確認 MariaDB 容器是否運行：`docker-compose ps`
   - 檢查網絡連接 　`docker-compose exec wordpress ping mariadb`

2. **Nginx 502 錯誤**
   - 檢查 WordPress 容器是否運行
   - 查看 Nginx 錯誤日誌

3. **WordPress 安裝問題**
   - 確保正確的資料庫憑證
   - 檢查文件權限

### 日誌位置

- WordPress 錯誤日誌：在 WordPress 容器中的 `/var/log/apache2/error.log`
- Nginx 錯誤日誌：在 Nginx 容器中的 `/var/log/nginx/error.log`
- MariaDB 錯誤日誌：在 MariaDB 容器中的 `/var/log/mysql/error.log`

## 安全性

### 安全性最佳實踐

1. 定期更新 Docker 映像
2. 使用強密碼
3. 實施 SSL/TLS 加密
4. 限制 WordPress 管理員訪問
5. 定期備份數據

### SSL 配置

要啟用 SSL，需要：

1. 將 SSL 證書和私鑰放在 `nginx/certs` 目錄中
2. 修改 Nginx 配置以使用 SSL
    - 將證書（cert.crt）和私鑰（key.key）放入 ./nginx/certs
    - 修改 default.conf，添加：

    ```sh
        server {
            listen 80;
            # 重定向 HTTP 到 HTTPS
            return 301 https://$host$request_uri;
        }
        server {
            listen 443 ssl;
            ssl_certificate /etc/nginx/certs/cert.crt;
            ssl_certificate_key /etc/nginx/certs/key.key;
        }
    ```
3. 重啟 Nginx：`docker-compose restart nginx`
4. 更新 WordPress URL 設置

## 部署

### 測試環境

1. 使用 Docker Compose 啟動測試環境
2. 執行功能測試
3. 驗證性能和安全性

### 生產環境

1. 使用 Docker Compose 或 Docker Swarm 部署
2. 設置適當的資源限制（CPU、內存）
3. 實施監控和日誌收集
4. 配置自動備份

## 附錄

### 有用的 Docker 命令

```bash
# 啟動全部服務
docker-compose up -d

# 停止全部服務
docker-compose down

# 查看容器狀態
docker-compose ps

# 查看日誌
docker-compose logs -f [service_name]

# 進入容器
docker-compose exec [service_name] bash

# 重啟單個服務
docker-compose restart [service_name]
```

### 相關資源

- [WordPress 開發文檔](https://developer.wordpress.org/)
- [Docker 文檔](https://docs.docker.com/)
- [Nginx 文檔](https://nginx.org/en/docs/)
- [Redis 文檔](https://redis.io/documentation)