# 本地開發環境建構指南

## 前置需求

1. 已安裝 Docker 和 Docker Compose
2. 已安裝 Git
3. 擁有專案的存取權限
4. 已準備好開發域名（建議使用 .dev 結尾）

## 建構步驟

### 1. 建立專案目錄

```bash
# 建立專案目錄
mkdir -p /var/www/products
cd /var/www/products

# Clone 專案
git clone [repository-url] [repository_name]
cd [repository_name]
```

### 2. 設定環境變數

```bash
# 複製環境變數範本
cp .env.example .env

# 編輯 .env 文件，設定：
# 基本設定
PROJECT_NAME=your_project    # 專案名稱
NGINX_HOST=your-domain.dev  # 開發域名
ENV_TYPE=dev               # 環境類型

# 資料庫設定
MYSQL_ROOT_PASSWORD=your_root_password
MYSQL_DATABASE=your_db_name
MYSQL_USER=your_db_user
MYSQL_PASSWORD=your_db_password

# PHP 設定
PHP_MEMORY_LIMIT=256M
MAX_EXECUTION_TIME=120
UPLOAD_MAX_FILESIZE=32M
POST_MAX_SIZE=32M
```

### 3. 生成 SSL 證書

```bash
# 設定腳本執行權限
chmod +x scripts/generate-ssl.sh

# 執行 SSL 證書生成腳本
./scripts/generate-ssl.sh

# 依序輸入：
# 1. 專案名稱（與 .env 中的 PROJECT_NAME 相同）
# 2. 選擇環境類型（輸入 1 選擇 dev）
# 3. 輸入開發域名（與 .env 中的 NGINX_HOST 相同）
```

### 4. 設定本地域名

編輯 hosts 文件：
- macOS/Linux: `/etc/hosts`
- Windows: `C:\Windows\System32\drivers\etc\hosts`

添加以下內容：
```
127.0.0.1 your-domain.dev
```

### 5. 信任本地 SSL 證書

#### macOS
```bash
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain nginx/certs/dev_${PROJECT_NAME}.crt
```

#### Windows
1. 按兩下 `nginx/certs/dev_${PROJECT_NAME}.crt`
2. 點擊「安裝證書」
3. 選擇「本機電腦」
4. 選擇「將所有證書放入以下存放區」
5. 瀏覽並選擇「受信任的根憑證授權單位」
6. 完成安裝

#### Linux (Ubuntu/Debian)
```bash
sudo cp nginx/certs/dev_${PROJECT_NAME}.crt /usr/local/share/ca-certificates/
sudo update-ca-certificates
```

### 6. 設定 Nginx 配置

```bash
# 確認配置模板存在
ls nginx/conf.d/dev.conf.template

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

### 7. 建立容器並啟動服務

```bash
# 構建並啟動所有容器
# 這會自動執行 generate-nginx-conf.sh
docker-compose up -d

# 確認所有容器都正常運行
docker-compose ps

# 檢查 Nginx 狀態
docker-compose exec nginx nginx -t
```

### 7. 初始化 WordPress

首次設定：
1. 在瀏覽器中訪問 https://your-domain.dev
2. 選擇語言
3. 完成 WordPress 初始設定：
   - 設定網站標題
   - 創建管理員帳號
   - 設定管理員密碼
   - 設定管理員電子郵件

### 8. 匯入開發資料（如果需要）

```bash
# 執行資料匯入腳本
./scripts/import-data.sh backups/database_[timestamp].sql backups/wp_backup_[timestamp].tar.gz
```

### 9. 確認環境正常運作

1. 確認網站可以通過 HTTPS 訪問
2. 確認可以正常登入 WordPress 後台
3. 確認資料庫連接正常
4. 確認 Redis 緩存正常運作

## 常見問題排除

### SSL 證書問題

1. 證書不受信任
   - 確認證書名稱格式正確（dev_${PROJECT_NAME}.crt）
   - 重新執行證書信任步驟
   - 檢查證書路徑和權限

2. 無法訪問 HTTPS
   - 確認 443 端口未被佔用
   ```bash
   lsof -i :443
   ```
   - 檢查 Nginx 配置生成是否正確
   ```bash
   docker-compose exec nginx cat /etc/nginx/conf.d/default.conf
   ```

### 容器相關問題

1. 容器無法啟動
   ```bash
   # 查看容器日誌
   docker-compose logs [service-name]
   ```

2. 資料庫連接失敗
   - 確認環境變數設定正確
   - 檢查資料庫容器狀態
   ```bash
   docker-compose ps mariadb
   docker-compose logs mariadb
   ```

### WordPress 問題

1. 白屏或 500 錯誤
   - 檢查 PHP 錯誤日誌
   ```bash
   docker-compose exec wordpress tail -f /var/log/php-fpm.log
   ```

2. 權限問題
   ```bash
   # 修復文件權限
   docker-compose exec wordpress chown -R www-data:www-data /var/www/html
   ```

## 開發工具建議

1. WordPress CLI
```bash
# 執行 WP-CLI 命令
docker-compose exec wordpress wp --info

# 更新核心
docker-compose exec wordpress wp core update

# 管理插件
docker-compose exec wordpress wp plugin list
```

2. 除錯設定
```bash
# 在 wp-config.php 中添加：
define('WP_DEBUG', true);
define('WP_DEBUG_LOG', true);
define('WP_DEBUG_DISPLAY', false);
```

## 環境管理

### 停止環境
```bash
docker-compose down
```

### 重啟環境
```bash
docker-compose restart
```

### 查看日誌
```bash
# 查看所有容器日誌
docker-compose logs -f

# 查看特定容器日誌
docker-compose logs -f [service-name]
```

### 清理環境
```bash
# 停止並移除容器
docker-compose down

# 清理未使用的映像
docker system prune

# 完整清理（包括數據卷）
docker-compose down -v
docker system prune -a
```

## 性能優化

1. 啟用 Redis 對象緩存
2. 配置 PHP OPcache
3. 使用 Nginx FastCGI 緩存
4. 優化資料庫查詢
5. 啟用瀏覽器緩存

## 安全建議

1. 使用強密碼
2. 定期更新所有組件
3. 限制管理員訪問
4. 監控錯誤日誌
5. 定期備份數據
