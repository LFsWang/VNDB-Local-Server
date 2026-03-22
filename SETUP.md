# VNDB 本地站點 Docker 建置指南

本文件說明如何在一台全新的電腦上，使用本專案的資料建立本地 VNDB 站點。

## 前置需求

- [Docker Desktop](https://www.docker.com/products/docker-desktop/) (含 Docker Compose)
- 約 2 GB 可用磁碟空間（映像 + 資料庫）

## 專案結構

```
VNDBDocker/
├── vndb/                          # VNDB 原始碼
├── vndb-db-2026-03-21.tar.zst     # 資料庫 dump（約 175 MB）
├── vndb-tags-2026-03-21.json.gz   # Tag dump（供參考）
├── vndb-traits-2026-03-21.json.gz # Trait dump（供參考）
├── vndb-votes-2026-03-21.gz       # 投票 dump（供參考）
├── docker-compose.yml             # Docker Compose 設定
├── init-vndb.sh                   # 自動初始化腳本
├── README.md                      # 原始 VNDB dump 格式說明
└── SETUP.md                       # 本文件
```

## 準備 VNDB 原始碼

`vndb/` 目錄需自行準備（不包含在本 repo 中）。取得原始碼後，需修改以下檔案：

### 修改 `vndb/conf_example.pl`

將 `cookie_defaults` 中的 `domain` 移除，否則在 localhost 環境下所有網頁會回傳 500 錯誤（FU 框架的 domain 驗證不接受沒有 `.` 的主機名）：

```perl
# 修改前
cookie_defaults => { domain => 'localhost', path => '/' },

# 修改後
cookie_defaults => { path => '/' },
```

> 如果容器已經初始化過，也需要同步修改 `vndb/docker/var/conf.pl` 中的相同設定，或刪除 `vndb/docker/pg17` 重新初始化。

## 快速開始

### 1. 建置 Docker 映像

```bash
docker compose build
```

首次建置約需 2-3 分鐘，會安裝 Alpine Linux、PostgreSQL 17、Perl 及所有相依套件。

### 2. 啟動容器

```bash
docker compose up -d
```

首次啟動時，`init-vndb.sh` 會自動執行以下步驟（約 10-20 分鐘）：

1. 建立容器內的開發使用者
2. 編譯安裝 vndbid PostgreSQL 擴充
3. 安裝 zstd 解壓工具
4. 編譯前端資源（JS、CSS、圖示）
5. 初始化 `var/` 目錄與設定檔
6. 初始化 PostgreSQL 資料庫
7. 匯入資料 dump（解壓 tar.zst → 建立 schema → 匯入各資料表）
8. 生成變更紀錄（使網頁詳細頁面可正常運作）
9. 重建快取（VN 快取、投票統計、標籤、特徵、搜尋索引）
10. 啟動開發伺服器

可透過以下指令觀察初始化進度：

```bash
docker logs -f vndb
```

看到以下訊息即代表啟動完成：

```
==========================================
  VNDB is ready at http://localhost:3000
  API: http://localhost:3000/api/kana
==========================================
```

### 3. 驗證

開啟瀏覽器造訪 http://localhost:3000，或測試 API：

```bash
# 查詢統計資料
curl http://localhost:3000/api/kana/stats

# 查詢特定 VN
curl -X POST http://localhost:3000/api/kana/vn \
  -H "Content-Type: application/json" \
  -d '{"filters":["id","=","v11"],"fields":"id,title"}'
# 回傳: {"more":false,"results":[{"id":"v11","title":"Fate/stay night"}]}

# 查詢角色
curl -X POST http://localhost:3000/api/kana/character \
  -H "Content-Type: application/json" \
  -d '{"filters":["id","=","c1"],"fields":"id,name"}'

# 列出前 5 筆 VN
curl -X POST http://localhost:3000/api/kana/vn \
  -H "Content-Type: application/json" \
  -d '{"filters":["id",">=","v1"],"fields":"id,title","results":5,"sort":"id"}'
```

## 常用操作

### 停止容器

```bash
docker compose down
```

### 重新啟動（資料保留）

```bash
docker compose up -d
```

再次啟動時不會重新匯入資料，直接啟動伺服器，僅需數秒。

### 進入容器 Shell

```bash
docker exec -ti vndb su -l devuser
```

### 進入 PostgreSQL

```bash
docker exec -ti vndb psql -U vndb
```

### 完全重置（清除所有資料重新匯入）

```bash
docker compose down
rm -rf vndb/docker/pg17
docker compose up -d
```

## API 說明

API 端點位於 `http://localhost:3000/api/kana`，使用方式與官方 API 相同。

- API 文件頁面：http://localhost:3000/api/kana
- 所有查詢端點使用 `POST` 方法，送出 JSON body
- 支援的端點：`/vn`、`/character`、`/release`、`/producer`、`/staff`、`/tag`、`/trait`、`/user`、`/ulist`、`/quote`
- 其他端點：`GET /stats`、`GET /schema`

### 查詢範例

```bash
# 用 ID 查詢
curl -X POST http://localhost:3000/api/kana/vn \
  -H "Content-Type: application/json" \
  -d '{"filters":["id","=","v2002"],"fields":"id,title,olang,image.url"}'

# 用多條件篩選
curl -X POST http://localhost:3000/api/kana/vn \
  -H "Content-Type: application/json" \
  -d '{"filters":["and",["olang","=","ja"],["id",">=","v1"]],"fields":"id,title","results":10,"sort":"id"}'

# 查詢 Release
curl -X POST http://localhost:3000/api/kana/release \
  -H "Content-Type: application/json" \
  -d '{"filters":["id","=","r1"],"fields":"id,title,released"}'

# 查詢 Tag
curl -X POST http://localhost:3000/api/kana/tag \
  -H "Content-Type: application/json" \
  -d '{"filters":["id","=","g1"],"fields":"id,name"}'
```

## 已知限制

| 項目 | 說明 |
|------|------|
| 圖片 | 無法顯示 VN 封面、角色圖、截圖等，因為圖片檔案不包含在資料庫 dump 中。 |
| extlinks 資料表 | `producers_extlinks`、`releases_extlinks`、`staff_extlinks`、`vn_extlinks` 匯入失敗（schema 欄位不匹配），外部連結資料不可用。 |
| ulist_labels | 使用者清單標籤未匯入（dump 不含 private 欄位）。 |
| vn_length_votes | 遊戲時長投票未匯入。 |
| 討論區 / 編輯紀錄 | Dump 本身不包含這些資料。 |
| API 文件頁 | `GET /api/kana` 需 `make prod`（依賴 pandoc）才能使用。API 端點本身不受影響。 |

## 快取重建

資料匯入後需要重建多項快取，API 的 `released`、`languages`、`platforms`、`developers`、`tags` 及 `search` 過濾器才能正常運作。初始化腳本會自動執行此步驟，但如需手動重建：

```bash
docker exec vndb sh -c "psql -U vndb vndb -c 'SELECT update_vncache(NULL);'"
docker exec vndb sh -c "psql -U vndb vndb -c 'SELECT update_vnvotestats();'"
docker exec vndb sh -c "psql -U vndb vndb -c 'SELECT tag_vn_calc(NULL);'"
docker exec vndb sh -c "psql -U vndb vndb -c 'SELECT traits_chars_calc(NULL);'"
docker exec vndb sh -c "psql -U vndb vndb -f sql/rebuild-search-cache.sql"
```

各步驟說明：

| 指令 | 用途 | 耗時 |
|------|------|------|
| `update_vncache(NULL)` | 重算 VN 的 `released`、`languages`、`platforms`、`developers` | 約 1 分鐘 |
| `update_vnvotestats()` | 重算評分、投票數、排名 | 約 30 秒 |
| `tag_vn_calc(NULL)` | 重建 `tags_vn_direct` 和 `tags_vn_inherit`（標籤繼承） | 約 2-5 分鐘 |
| `traits_chars_calc(NULL)` | 重建角色特徵繼承快取 | 約 1-2 分鐘 |
| `rebuild-search-cache.sql` | 重建全文搜尋索引（分批處理，避免鎖表） | 約 5-10 分鐘 |

若只需重建單一 VN 的快取，可傳入特定 ID：

```bash
docker exec vndb sh -c "psql -U vndb vndb -c \"SELECT update_vncache('v92');\""
docker exec vndb sh -c "psql -U vndb vndb -c \"SELECT tag_vn_calc('v92');\""
```

## 更新資料 dump

若要使用更新的資料 dump：

1. 從 https://dl.vndb.org/dump/ 下載新的 `vndb-db-*.tar.zst`
2. 將檔案放入專案根目錄
3. 修改 `docker-compose.yml` 中的檔案名稱：
   ```yaml
   - ./vndb-db-新日期.tar.zst:/dump/vndb-db.tar.zst:ro
   ```
4. 重置並重建：
   ```bash
   docker compose down
   rm -rf vndb/docker/pg17
   docker compose up -d
   ```

## 疑難排解

### 容器啟動後立即退出

檢查日誌：
```bash
docker logs vndb
```

常見原因：port 3000 被占用。可在 `docker-compose.yml` 中改為其他 port：
```yaml
ports:
  - "3001:3000"
```

### 資料庫初始化失敗

刪除 PostgreSQL 資料目錄後重試：
```bash
docker compose down
rm -rf vndb/docker/pg17
docker compose up -d
```

### 查看 API 錯誤紀錄

```bash
docker exec vndb cat /vndb/docker/var/log/fu.log
docker exec vndb cat /vndb/docker/var/log/api.log
```
