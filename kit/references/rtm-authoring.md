# RTM 建檔訪談指南（onboarding）

kit-init onboarding 或 `--rtm` 安裝後，matrix 內容從無到有的建檔流程。由 SKILL（LLM）執行——installer 只 scaffold 目錄與空範本（`kit/templates/rtm/matrix-example.yaml`），內容建檔一律走本指南。

## 路徑選擇（第一問）

問使用者一題定路徑：**「這個專案有正式需求文件（RFP／建議書／規格書／合約附件）嗎？」**

- 有 → **路徑 A：正式文件抽取**（需求文件是權威，matrix 從文件長出來）
- 無 → **路徑 B：as-built 反向盤點**（程式現況是唯一真理，matrix 從 code 長出來）

選定後立即寫入 progress 檔（見「中斷恢復」）。兩路產出同一 schema（見 matrix-example.yaml），差別只在權威來源與 status 初值。

## 路徑 A：正式文件抽取

參照 pm-init 的抽取模式（`pm-engine/skills/pm-init`）：格式偵測 → 自動抽取 → 判斷題校正 → 機器驗證。

### A1. 文件格式偵測與轉文字

請使用者指出文件路徑，依副檔名依序嘗試：

| 格式 | 指令 |
|---|---|
| .docx / .doc | `textutil -convert txt -stdout <檔>` |
| .md / .txt | 直接讀 |
| .pdf | `pdftotext <檔> -`（OCR 版 PDF 會吃編號——條號錯亂時明示「階層權威＝原 PDF」，逐節人工核對編號） |

轉換失敗的段落標 `_todo` 留待人工，不猜。

### A2. 條目草稿

逐章節抽取需求條文 → 產 matrix 草稿檔（一章節一檔，放 `matrix_dir`）：

- `req_id`＝章節階層路徑（如 `一、系統功能需求/（一）某章節/3`）；`req_text`＝條文原文（不改寫）
- `detail_specs` 先留最小描述或空、`status` 先統一給初值（A3 校正）
- 每檔 `meta.section`＋`meta.total_clauses`（＝該檔條目數，機器對帳錨點）

### A3. 判斷題校正（逐檔，每題單選）

草稿完成後對使用者跑判斷題——只問影響結構的三類，不問開放題：

1. **章節切檔粒度**：目前一章節一檔切法 OK？還是太細（併檔）／太粗（拆檔）？——切錯檔粒度後期重排成本最高，先問
2. **req_id 命名**：沿用文件原始編號階層？還是專案自訂前綴？（一旦入 commit 就是錨點，改名＝全庫 ref 失效）
3. **status 初值**：這批條目預設 `planned`（綠地專案）還是逐條問 `implemented`／`partial`（文件與既有實作並存的棕地專案）？棕地 → 逐檔列條目讓使用者勾已實作項，勾中的補 `impl_details`

每校正完一個章節檔，更新 progress 檔的已校正清單。

### A4. rtm-check 驗證

全部章節校正完跑 `spec_check` 宣告的指令（如 `pnpm tsx <kit_root>/engines/rtm-check.ts`）：

- PASS → 建檔完成，刪 progress 檔，引導 commit
- FAIL → 逐條修（常見：total_clauses 沒對上、非 planned 條目缺 impl_details、divergent 缺 notes）→ 重跑到綠

## 路徑 B：as-built 反向盤點

無正式文件——不編需求，只盤點「現在系統做得到什麼」。

### B1. 掃描功能面

依專案型態掃入口面（擇一或多）：

| 型態 | 掃描目標 |
|---|---|
| Web 前端 | routes／pages 目錄（如 `app/**/page.tsx`、router 定義） |
| API | tRPC routers／REST endpoints／GraphQL schema |
| CLI | 子指令表（argparse／commander 定義、`--help` 輸出） |

每個入口配一句行為描述（從 code 讀出，不腦補）。

### B2. 功能清單使用者確認

把掃描結果整理成功能清單（分群、每項一句話）呈現，讓使用者：勾掉不算功能的（內部工具頁、debug 入口）、補漏掃的、修正描述。**確認過的清單才是條目來源**——跳過此步＝把掃描雜訊固化成規格。

### B3. 產單檔 matrix

- 單檔起步（如 `<matrix_dir>/000-as-built.yaml`），`meta.section` 取專案名或「as-built 盤點」；日後功能長大再拆檔
- 每項功能一條目：`req_id` 自訂序號、`req_text`＝功能一句話、**`status` 一律 `implemented`**（as-built＝盤點現況，沒有 planned）、`detail_specs` 寫使用者可感知行為、`impl_details` 寫掃描時定位到的檔案錨點
- 跑 rtm-check 驗證到綠（同 A4），刪 progress 檔，引導 commit

## 中斷恢復

訪談跨多輪、可能中斷。progress 檔＝`.kit-init-progress.yaml`（專案根，**由 SKILL（LLM）讀寫，installer 無感**），只記兩件事：

```yaml
rtm_path: A            # A=文件抽取 | B=as-built
corrected_sections:    # 路徑 A 已完成判斷題校正的章節檔
- 101-某章節.yaml
```

不記逐題答案、不記草稿內容——草稿本身就在 matrix_dir，狀態以檔案為準。

**恢復判準**：matrix_dir 有草稿檔存在但 rtm-check 未過 → 視為建檔中斷，讀 progress 檔續跑（路徑 A 從第一個不在 corrected_sections 的章節續；路徑 B 重呈 B2 清單確認）。rtm-check 已過 → 建檔已完成，殘留 progress 檔直接刪。progress 檔遺失 → 不阻塞：從 matrix 現況推路徑（有 planned 條目或多檔＝多半路徑 A），重問路徑選擇一題即可恢復。

## 附註：裁定記錄

- **wave 合約層與 sdd 傳遞（裁定）**：wave 工作項的 matrix 條目 ref（dashboard `matrix` 欄）寫進工作項段落本文 → sdd task-brief 以 awk 全文抽取工作項段落時**自動連帶傳遞**給 implementer，**task-brief 機制零改動**。此為有意識的裁定（非遺漏）：不另開欄位協定、不改 sdd。
- **rtm-index 的 .gitignore 條目**：`.claude/kit/rtm-index.tsv`（rtm-check --emit-index 衍生物）之 gitignore 條目由 `installers/modules/rtm.sh` 冪等 append——本指南僅記載，實作歸 installer（🤖-4）。
