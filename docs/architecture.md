# SrLWordpress 專案架構文檔

## 專案概述

SrLWordpress 是一個基於 Docker 的 WordPress 開發環境，採用現代化的容器技術來簡化開發流程並提高效率。該專案使用 Docker Compose 協調多個服務容器，包括 WordPress、MariaDB、Nginx 和 Redis，提供高效能且易於維護的網站開發環境。專案特別針對 Linode Nanode 1GB 方案進行了優化。

## 系統架構

### 容器服務

本專案包含以下 Docker 容器服務：

1. **WordPress (wp_app)**
   - 基於 PHP 8.2 FPM 的自定義映像
   - 包含必要的 PHP 擴展（GD、MySQLi、PDO）
   - 預裝 WP-CLI 工具
   - 記憶體限制：300MB，預留 200MB
   - Redis 對象緩存整合

2. **MariaDB (wp_db)**
   - 使用最新版本的 MariaDB
   - 記憶體限制：300MB，預留 200MB
   - 數據持久化存儲
   - 連接數優化配置

3. **Nginx (wp_nginx)**
   - Alpine 版本的 Nginx
   - 記憶體限制：128MB，預留 64MB
   - SSL/TLS 支援
   - 靜態文件優化
   - FastCGI 緩存

4. **Redis (wp_redis)**
   - 記憶體限制：128MB，預留 64MB
   - 最大記憶體使用：100MB
   - LRU 緩存策略
   - 對象緩存配置

### 目錄結構

```
/var/www/products/[repository_name]/
├── .env                 # 環境變數配置
├── .env.example         # 環境變數範例
├── docker-compose.yml   # 容器編排配置
├── db_data/            # 資料庫數據（不納入版控）
├── docs/               # 專案文檔
│   ├── architecture.md     # 架構文檔
│   ├── technical-guide.md  # 技術指南
│   ├── deployment-guide.md # 部署指南
│   └── ssl-setup.md       # SSL 設定指南
├── docker/             # Docker 配置
│   └── wp/            # WordPress 容器
│       ├── Dockerfile # 容器定義
│       └── php.ini    # PHP 配置
├── nginx/              # Nginx 配置
│   ├── conf.d/        # 站點配置
│   │   ├── default.conf      # 動態生成的配置
│   │   ├── dev.conf.template # 開發環境模板
│   │   └── prod.conf.template # 生產環境模板
│   └── certs/         # SSL 證書
│       └── .gitkeep
├── scripts/           # 工具腳本
│   ├── export-data.sh       # 數據導出
│   ├── import-data.sh       # 數據導入
│   ├── generate-ssl.sh      # SSL 證書生成
│   └── generate-nginx-conf.sh # Nginx 配置生成
└── wp/                # WordPress 文件
    └── .gitkeep
```

### Nginx 配置架構

#### 配置管理流程

1. **配置模板**
   - dev.conf.template：開發環境配置模板
   - prod.conf.template：生產環境配置模板
   - 使用環境變數進行動態替換

2. **自動化配置生成**
   - 通過 generate-nginx-conf.sh 腳本生成
   - 容器啟動時自動執行
   - 根據環境變數選擇適當模板

3. **環境變數整合**
   ```ini
   PROJECT_NAME=project    # 用於 SSL 證書命名
   NGINX_HOST=domain      # 網站域名
   ENV_TYPE=dev|prod     # 環境類型
   ```

4. **配置驗證機制**
   - 生成時自動檢查語法
   - 支援配置重載
   - 錯誤處理和日誌記錄

## 配置詳情

### 環境變數

專案使用 `.env` 文件管理環境變數：

```ini
# PHP 設定
PHP_MEMORY_LIMIT=256M
MAX_EXECUTION_TIME=120
UPLOAD_MAX_FILESIZE=32M
POST_MAX_SIZE=32M

# MySQL 設定
MYSQL_ROOT_PASSWORD=
MYSQL_DATABASE=
MYSQL_USER=
MYSQL_PASSWORD=
MYSQL_MAX_CONNECTIONS=50
```

### 網絡配置

- 所有容器使用 bridge 網絡
- 容器間通過服務名稱互相訪問
- 外部訪問通過 Nginx 反向代理

### 端口映射

- HTTP: 80
- HTTPS: 443
- MariaDB: 9001 (內部 3306)
- Redis: 9002 (內部 6379)

## SSL 證書管理

### 證書命名規則

- 開發環境：dev_{project_name}.key/crt
- 生產環境：prod_{project_name}.key/crt

### 證書生成

使用 generate-ssl.sh 腳本：
1. 輸入專案名稱
2. 選擇環境（dev/prod）
3. 輸入域名

## 性能優化

### 1. PHP 優化
- 記憶體限制：256MB
- 執行時間：120秒
- 上傳限制：32MB
- OPcache 配置優化

### 2. Nginx 優化
- 靜態文件緩存
- FastCGI 緩衝配置
- Gzip 壓縮
- 連接數優化

### 3. MariaDB 優化
- 連接數限制：50
- 查詢緩存配置
- InnoDB 緩衝池優化

### 4. Redis 優化
- 最大記憶體：100MB
- LRU 淘汰策略
- 持久化配置

## 資源限制

針對 Nanode 1GB 方案的優化：

1. **記憶體分配**
   - WordPress: 300MB
   - MariaDB: 300MB
   - Nginx: 128MB
   - Redis: 128MB
   - 系統預留: ~144MB

2. **Swap 配置**
   - 大小：2GB
   - Swappiness：10
   - Cache pressure：50

## 安全考量

1. **文件安全**
   - 敏感信息使用環境變數
   - 嚴格的文件權限控制
   - 禁止訪問隱藏文件

2. **SSL/TLS**
   - 強制 HTTPS
   - 最低 TLS 1.2
   - HSTS 支援

3. **容器安全**
   - 資源限制
   - 容器隔離
   - 最小權限原則

## 備份策略

1. **數據備份**
   - 資料庫完整備份
   - WordPress 文件備份
   - 配置文件備份

2. **備份管理**
   - 保留期：7天
   - 自動清理
   - 備份驗證

## 擴展性

1. **水平擴展**
   - 可添加更多 WordPress 容器
   - 可配置負載均衡
   - 可擴展緩存層

2. **功能擴展**
   - 支援 WordPress 插件
   - 可添加額外服務
   - 可自定義構建流程

3. **監控擴展**
   - 支援 Netdata
   - 日誌管理
   - 性能監控
