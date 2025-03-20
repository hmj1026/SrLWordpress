# SrLWordpress

一個基於 Docker 的高效 WordPress 開發環境。

## 特點

- 使用 Nginx 作為 Web 服務器，提供高效靜態文件處理和反向代理
- MariaDB 作為持久化數據庫，支持 WordPress 數據存儲
- Redis 對象緩存，提升網站性能和響應速度
- 通過環境變量管理敏感信息，增強安全性
- 提供詳細的架構文檔和技術指南

## 快速開始

### 前置條件

- 已安裝 [Docker](https://docs.docker.com/get-docker/) 和 [Docker Compose](https://docs.docker.com/compose/install/)
- 已安裝 [Git](https://git-scm.com/downloads)

### 安裝步驟

1. **CLONE**

```bash
   git clone https://github.com/yourusername/SrLWordpress.git
   cd SrLWordpress
```

2. 配置環境變量

```bash
cp .env.example .env
```

編輯 `.env` 文件，設置數據庫憑證。

3. 啟動服務

```bash
docker-compose up -d
```

4. 訪問 WordPress

在瀏覽器中打開 `http://localhost`

## 架構

完整的架構文檔請查看 [architecture.md](docs/architecture.md)。

## 使用說明

### 數據庫管理

使用任意 MySQL 客戶端連接到 `localhost:9001`：

- 使用者: `.env` 中的 `MYSQL_USER`
- 密碼: `.env` 中的 `MYSQL_PASSWORD`
- 數據庫: `.env` 中的 `MYSQL_DATABASE`

### Redis 管理

使用 Redis 客戶端連接到 `localhost:9002`。

### WordPress 開發

WordPress 文件位於 `wp` 目錄。該目錄與容器內的 `/var/www/html` 掛載同步。

## 工具

### WP-CLI

可以通過以下方式使用 WP-CLI：

```bash
docker-compose exec wordpress wp --info
```