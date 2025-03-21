# SrLWordpress

一個基於 Docker 的高效 WordPress 開發環境，特別針對 Linode Nanode 1GB 方案優化。

## 特點

- 使用 Nginx 作為 Web 服務器，提供高效靜態文件處理和反向代理
- MariaDB 作為持久化數據庫，支持 WordPress 數據存儲
- Redis 對象緩存，提升網站性能和響應速度
- 完整的環境變量管理系統
- 支援開發和生產環境的獨立配置
- 自動化的 SSL 證書管理
- 資源使用優化，適合小型服務器

## 快速開始

### 前置條件

- 已安裝 [Docker](https://docs.docker.com/get-docker/) 和 [Docker Compose](https://docs.docker.com/compose/install/)
- 已安裝 [Git](https://git-scm.com/downloads)
- 已準備好域名（開發環境可使用 *.dev 域名）

### 安裝步驟

1. **CLONE**

```bash
mkdir -p /var/www/products
cd /var/www/products
git clone [repository-url] [repository-name]
cd [repository-name]
```

2. **配置環境**

```bash
# 複製環境變數範本
cp .env.example .env

# 編輯 .env 文件，設定：
# - 資料庫憑證
# - 專案名稱（PROJECT_NAME）
# - 域名（NGINX_HOST）
# - 環境類型（ENV_TYPE）
```

3. **生成 SSL 證書**

```bash
# 設定腳本執行權限
chmod +x scripts/generate-ssl.sh

# 生成證書
./scripts/generate-ssl.sh
# 依照提示輸入必要信息
```

4. **啟動服務**

```bash
docker-compose up -d
```

5. **訪問網站**

在瀏覽器中訪問 https://your-domain

## 環境配置

### 開發環境

```ini
PROJECT_NAME=your_project
NGINX_HOST=your-domain.dev
ENV_TYPE=dev
```

### 生產環境

```ini
PROJECT_NAME=your_project
NGINX_HOST=your-domain.com
ENV_TYPE=prod
```

## 目錄結構

```
/var/www/products/[repository_name]/
├── docker/              # Docker 配置
├── nginx/              # Nginx 配置
│   ├── conf.d/        # 站點配置模板
│   └── certs/         # SSL 證書
├── scripts/           # 工具腳本
└── wp/                # WordPress 文件
```

## 使用指南

### 資料庫管理

使用任意 MySQL 客戶端連接：
- 主機：localhost:9001
- 使用者：.env 中的 MYSQL_USER
- 密碼：.env 中的 MYSQL_PASSWORD
- 資料庫：.env 中的 MYSQL_DATABASE

### Redis 管理

Redis 服務運行在 localhost:9002。

### WordPress 開發

WordPress 文件位於 wp 目錄，與容器內的 /var/www/html 同步。

### SSL 證書管理

```bash
# 生成新證書
./scripts/generate-ssl.sh

# 查看證書信息
openssl x509 -in nginx/certs/${ENV_TYPE}_${PROJECT_NAME}.crt -text -noout
```

## 工具腳本

### WP-CLI

```bash
docker-compose exec wordpress wp --info
```

### 數據備份/還原

```bash
# 備份
./scripts/export-data.sh

# 還原
./scripts/import-data.sh backups/database_[timestamp].sql backups/wp_backup_[timestamp].tar.gz
```

## 文檔

- [架構文檔](docs/architecture.md)
- [技術指南](docs/technical-guide.md)
- [部署指南](docs/deployment-guide.md)
- [SSL 設定](docs/ssl-setup.md)
- [本地開發指南](docs/local-dev-setup.md)

## 注意事項

1. 開發環境和生產環境使用不同的 Nginx 配置
2. SSL 證書命名格式：{env}_{project_name}.crt/key
3. 生產環境建議使用 Let's Encrypt 證書
4. 注意資源使用限制，特別是在 1GB RAM 環境中
