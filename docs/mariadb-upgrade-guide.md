# MariaDB 升級指南

## 概述

本指南協助你將現有的 SrLWordpress 專案升級至支援 MariaDB 11.7+ 的版本，主要是解決備份腳本的兼容性問題。

## 問題背景

### 變更內容
- **MariaDB 11.7+** 移除了 MySQL 兼容命令 (`mysql`, `mysqldump`)
- 新版本只支援原生 MariaDB 命令 (`mariadb`, `mariadb-dump`)
- `--column-statistics=0` 參數在 MariaDB 中不被支援

### 影響範圍
- 資料庫備份腳本 (`export-data.sh`)
- 手動資料庫操作命令
- 任何依賴 MySQL 命令的自定義腳本

## 升級步驟

### 1. 檢查當前環境

首先確認你的 MariaDB 版本：

```bash
# 檢查 MariaDB 版本
docker exec wp_db mariadb --version

# 檢查可用的命令
docker exec wp_db ls -la /usr/bin/ | grep -E "(mysql|mariadb)"
```

### 2. 更新備份腳本

#### A. 使用新的 V2 腳本（推薦）

```bash
# 設定執行權限
chmod +x scripts/export-data-v2.sh

# 測試新腳本
./scripts/export-data-v2.sh
```

#### B. 或者更新現有腳本

如果你想保留原有的腳本名稱，可以手動更新：

```bash
# 備份原腳本
cp scripts/export-data.sh scripts/export-data.sh.backup

# 手動編輯 scripts/export-data.sh
# 進行以下替換：
# 1. 將 mysqldump 替換為 mariadb-dump
# 2. 移除 --column-statistics=0 參數
```

具體修改內容：
```diff
- MYSQLDUMP_OPTS="... --column-statistics=0"
+ MYSQLDUMP_OPTS="... # 移除 --column-statistics=0"

- docker exec "$MYSQL_CONTAINER" mysqldump $MYSQLDUMP_OPTS
+ docker exec "$MYSQL_CONTAINER" mariadb-dump $MYSQLDUMP_OPTS
```

### 3. 更新文檔和配置

#### 更新 README.md

```bash
# 在 README.md 中的備份指令部分，添加註記：
# 使用 ./scripts/export-data-v2.sh 進行備份（MariaDB 11.7+ 兼容）
```

#### 更新個人腳本

如果你有任何自定義的資料庫操作腳本，也需要更新：

```bash
# 將這些命令
mysql -u... -p...
mysqldump -u... -p...

# 替換為
mariadb -u... -p...
mariadb-dump -u... -p...
```

### 4. 測試升級結果

#### 測試資料庫連接
```bash
# 測試 MariaDB 連接
docker exec wp_db mariadb -u${MYSQL_USER} -p${MYSQL_PASSWORD} -e "SHOW DATABASES;"
```

#### 測試備份功能
```bash
# 執行完整備份測試
./scripts/export-data-v2.sh

# 檢查備份文件
ls -la backups/
```

#### 測試還原功能
```bash
# 如果有測試環境，可以測試還原
./scripts/import-data.sh backups/backup_[timestamp].tar.gz
```

### 5. 清理與優化

#### 清理舊文件（可選）
```bash
# 如果確認 V2 腳本工作正常，可以移除舊的備份文件
rm -f scripts/export-data.sh.backup

# 或者重命名舊腳本為 legacy 版本
mv scripts/export-data.sh scripts/export-data-legacy.sh
```

## 故障排除

### 常見問題

#### 1. "executable file not found" 錯誤
```bash
# 錯誤：exec: "mysql": executable file not found
# 解決：使用 mariadb 命令替代 mysql
docker exec wp_db mariadb -u... -p...
```

#### 2. "unknown variable 'column-statistics'" 錯誤
```bash
# 錯誤：mariadb-dump: unknown variable 'column-statistics=0'
# 解決：從備份命令中移除此參數
```

#### 3. 權限問題
```bash
# 確保腳本有執行權限
chmod +x scripts/export-data-v2.sh
```

### 驗證升級成功

檢查以下項目確認升級成功：

1. **備份腳本正常運行**
   ```bash
   ./scripts/export-data-v2.sh
   ```

2. **生成的備份文件完整**
   ```bash
   # 檢查備份文件大小合理
   ls -lh backups/latest.tar.gz

   # 檢查備份內容
   tar -tzf backups/latest.tar.gz | head -10
   ```

3. **資料庫操作正常**
   ```bash
   docker exec wp_db mariadb -u${MYSQL_USER} -p${MYSQL_PASSWORD} -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${MYSQL_DATABASE}';"
   ```

## 回滾計劃

如果升級過程中遇到問題，可以按以下步驟回滾：

### 1. 還原備份腳本
```bash
# 如果有備份原腳本
cp scripts/export-data.sh.backup scripts/export-data.sh
```

### 2. 使用舊版 MariaDB（不推薦）
```bash
# 修改 docker-compose.yml 使用特定版本
# image: mariadb:10.6  # 支援 MySQL 兼容命令的舊版本
```

### 3. 切換到 MySQL（如果需要）
```bash
# 在 docker-compose.yml 中替換
# image: mysql:8.0
# 注意：需要調整環境變數和配置
```

## 最佳實踐

1. **定期測試備份**：確保備份腳本在每次環境更新後仍能正常工作
2. **保留多個版本**：同時保留新舊版本的腳本以應對不同環境
3. **文檔更新**：及時更新專案文檔反映最新的命令和流程
4. **自動化測試**：考慮建立自動化測試來驗證備份和還原功能

## 相關資源

- [MariaDB 官方文檔](https://mariadb.com/docs/)
- [MariaDB vs MySQL 命令對照](https://mariadb.com/kb/en/mysql-to-mariadb-migration/)
- [專案 README.md](../README.md)
- [架構文檔](architecture.md)