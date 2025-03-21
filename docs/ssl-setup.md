# SSL 證書設定指南

本文檔說明如何在不同環境中管理 SSL 證書。

## 證書命名規則

證書檔案採用以下命名格式：
- 開發環境：dev_{project_name}.crt/key
- 生產環境：prod_{project_name}.crt/key

例如，專案名稱為 "mysite" 時：
- 開發環境：dev_mysite.crt 和 dev_mysite.key
- 生產環境：prod_mysite.crt 和 prod_mysite.key

## 開發環境設定

### 1. 設定環境變數

編輯 `.env` 文件：
```ini
PROJECT_NAME=mysite          # 專案名稱
NGINX_HOST=mysite.dev       # 開發域名
ENV_TYPE=dev               # 環境類型
```

### 2. 生成自簽證書

```bash
# 設定執行權限
chmod +x scripts/generate-ssl.sh

# 執行證書生成腳本
./scripts/generate-ssl.sh

# 依序輸入：
# 1. 專案名稱
# 2. 選擇環境類型（dev）
# 3. 輸入域名
```

### 3. 信任本地證書

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

#### Linux
```bash
sudo cp nginx/certs/dev_${PROJECT_NAME}.crt /usr/local/share/ca-certificates/
sudo update-ca-certificates
```

### 4. 設定本地域名

編輯 hosts 文件：
- macOS/Linux: `/etc/hosts`
- Windows: `C:\Windows\System32\drivers\etc\hosts`

添加：
```
127.0.0.1 your-domain.dev
```

## 生產環境設定

### 1. 設定環境變數

編輯 `.env` 文件：
```ini
PROJECT_NAME=mysite          # 專案名稱
NGINX_HOST=mysite.com       # 生產域名
ENV_TYPE=prod              # 環境類型
```

### 2. Let's Encrypt 證書（推薦）

```bash
# 安裝 certbot
apt install -y certbot

# 申請證書
certbot certonly --webroot \
  -w /var/www/products/[repository_name]/public \
  -d your-domain.com

# 複製並重命名證書
cp /etc/letsencrypt/live/your-domain.com/fullchain.pem nginx/certs/prod_${PROJECT_NAME}.crt
cp /etc/letsencrypt/live/your-domain.com/privkey.pem nginx/certs/prod_${PROJECT_NAME}.key

# 設定自動更新
echo "0 0 1 * * certbot renew --quiet && docker-compose restart nginx" | crontab -
```

### 3. 自簽證書（測試用）

如果只是測試用途，也可以使用自簽證書：

```bash
./scripts/generate-ssl.sh
# 選擇 prod 環境並輸入域名
```

## Nginx 配置

系統會根據環境變數自動選擇正確的配置模板：

### 開發環境 (dev.conf.template)
- 較寬鬆的安全設定
- 更長的超時時間
- 更大的上傳限制

### 生產環境 (prod.conf.template)
- 嚴格的安全標頭
- 最佳化的性能設定
- 額外的安全限制

## 證書管理

### 查看證書信息

```bash
# 查看證書詳細信息
openssl x509 -in nginx/certs/${ENV_TYPE}_${PROJECT_NAME}.crt -text -noout

# 檢查證書有效期
openssl x509 -in nginx/certs/${ENV_TYPE}_${PROJECT_NAME}.crt -noout -dates
```

### 證書備份

```bash
# 備份證書
tar -czf ssl-backup.tar.gz nginx/certs/
```

### 證書更新

1. 開發環境：重新執行 generate-ssl.sh
2. 生產環境：
   - Let's Encrypt：等待自動更新
   - 自簽證書：重新執行 generate-ssl.sh

## 故障排除

### 常見問題

1. 證書不受信任
   - 確認證書已正確安裝到系統信任存儲
   - 檢查證書路徑和權限
   - 確認證書名稱格式正確

2. 證書不匹配
   - 確認環境變數設定正確
   - 檢查 Nginx 配置中的證書路徑
   - 確認域名與證書匹配

3. 憑證過期
   - 開發環境：重新生成證書
   - 生產環境：檢查 Let's Encrypt 自動更新

### 安全建議

1. 定期更新證書
2. 使用強加密套件
3. 啟用 HSTS
4. 限制 SSL 協議版本
5. 保護證書私鑰
