# SrLWordpress 專案架構文檔

## 專案概述

SrLWordpress 是一個基於 Docker 的 WordPress 開發環境，採用現代化的容器技術來簡化開發流程並提高效率。該專案使用 Docker Compose 協調多個服務容器，包括 WordPress、MariaDB、Nginx 和 Redis，提供高效能且易於維護的網站開發環境。

## 系統架構

### 容器服務

本專案包含以下 Docker 容器服務：

1. **WordPress (wp_app)**
   - 基於 PHP 8.2 FPM 的自定義映像，包含 GD、MySQLi、PDO 等 PHP 擴展
   - 預裝 WP-CLI 工具，方便執行 WordPress 命令行操作
   - 配置 Redis 作為對象緩存，提升性能

2. **MariaDB (wp_db)**
   - 使用最新版本的 MariaDB 作為 WordPress 的資料庫
   - 數據持久化存儲在 `./db_data` 目錄

3. **Nginx (wp_nginx)**
   - 使用 Alpine 版本的 Nginx 作為反向代理服務器
   - 處理靜態文件服務和 PHP 請求轉發至 WordPress 容器
   - 配置了緩存和安全設置，支持 HTTP 和 HTTPS

4. **Redis (wp_redis)**
   - 使用最新版本的 Redis 作為 WordPress 的對象緩存
   - 提升網站性能和響應速度

### 目錄結構


```
SrLWordpress/
├── .env                 # 環境變數配置文件
├── .env.example         # 環境變數範例文件
├── docker-compose.yml   # Docker Compose 配置文件
├── db_data/             # MariaDB 資料持久化目錄
├── docs/                # 專案文檔目錄
│   └── architecture.md  # 架構文檔
├── docker/              # Docker 構建相關文件
│   └── wp/              # WordPress 容器構建目錄
│       ├── Dockerfile   # WordPress 容器構建文件
│       └── php.ini      # PHP 配置文件
├── nginx/               # Nginx 配置目錄
│   ├── conf.d/          # Nginx 站點配置
│   │   └── default.conf # 默認站點配置
│   └── certs/           # SSL 證書目錄
└── wp/                  # WordPress 目錄（共享卷）
```

## 配置詳情

### 環境變數

專案使用 `.env` 文件管理環境變數，包括：

- `MYSQL_ROOT_PASSWORD`: MariaDB root 用戶密碼
- `MYSQL_DATABASE`: WordPress 資料庫名稱
- `MYSQL_USER`: WordPress 資料庫用戶
- `MYSQL_PASSWORD`: WordPress 資料庫密碼

### 網絡配置

所有容器連接到名為 `wp_network` 的橋接網絡，確保容器間通訊順暢。

### 端口映射

- Nginx: 80 (HTTP) 和 443 (HTTPS)
- MariaDB: 9001 -> 3306
- Redis: 9002 -> 6379
- WordPress (內部): PHP-FPM 使用 9000 端口與 Nginx 通訊

## 開發指南

### 啟動環境

```bash
docker-compose up -d
```

### 停止環境

```bash
docker-compose down
```

### 訪問網站

在瀏覽器中訪問 `http://localhost`

### 資料庫管理

可以使用任意 MySQL 管理工具，連接到 `localhost:9001`

### Redis 管理

可以使用 Redis CLI 或 GUI 工具，連接到 `localhost:9002`

## 性能優化

1. **PHP 優化**
   - 內存限制設為 256M
   - 啟用 OPcache（128M 內存，4000 個文件上限）
   - 文件上傳限制設為 64M，執行時間上限為 300 秒

2. **Nginx 優化**
   - 靜態文件設置長期緩存（expires max）
   - FastCGI 緩衝區優化（16k x 16 緩衝區，32k 緩衝大小）
   - 支持高效 PHP 請求處理

3. **Redis 緩存**
   - 配置為 WordPress 對象緩存，減少資料庫負載
   - 通過 WP_REDIS_HOST 連接到 Redis 容器

## 安全考量

1. 使用 .env 文件存儲敏感信息，避免硬編碼
2. Nginx 配置禁止訪問隱藏文件（location ~ /\. deny all）
3. 容器化部署提供隔離層，增強安全性
4. 支持 SSL/TLS（需自行提供證書至 ./nginx/certs）

## 擴展性

該架構允許簡單地擴展功能：

1. 可添加 WordPress 插件或主題至 ./wp 目錄
2. 可調整 PHP（php.ini）和 Nginx（default.conf）配置
3. 可新增服務容器（如 Elasticsearch 或 Memcached）至 docker-compose.yml