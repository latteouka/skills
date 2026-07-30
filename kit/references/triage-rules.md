# Triage 判斷樹

對 `inbox.md` 中每一筆 `## INB-NNN` 執行下列步驟，結果寫入 `backlog/` 目錄（一筆一檔 `backlog/B-NNN.md`，ID 由 `~/projects/skills/kit/tools/next-id.sh --touch B` 原子取號）。

## -1. 先合併分片（inbox.d/ 存在時必做第一步）

多 session 並行時 capture.sh 把強信號寫進 `inbox.d/<sid8>.md` 分片（條目 id 為
臨時的 `CAP-HHMMSS`，不佔 INB 號）。triage 開始前：

1. 讀出全部 `inbox.d/*.md` 的 `## CAP-*` 條目，**依 when 排序**依次轉正——
   每筆給正式 `INB-NNN`（接續 high-water mark）append 進 `inbox.md`，
   `from` 欄補 `（自分片 <sid8>）`
2. 轉正完成後**刪除已消化的分片檔**（內容已在 inbox.md，留著會重複計數）
3. 更新 `<!-- INB-seq: NNN -->` 為新最大值
4. 再開始對 inbox.md 跑步驟 0 起的判斷樹

分片不存在或為空 → 跳過本步。

## 0. 兩個入口——分界是「判斷完成了沒」，不是「誰寫的」

**能填得出 `type` / `flow` / `matrix` 三個欄位 → 直接寫 `backlog/B-NNN.md`（`~/projects/skills/kit/tools/next-id.sh --touch B` 取號），跳過 inbox。**
**填不出來（或當下沒時間查證）→ 寫 `inbox.md`，等 triage。**

| 來源 | 走哪 | 為什麼 |
|---|---|---|
| 使用者隨口講、聊天中冒出的 bug | **inbox** | 捕捉必須零摩擦——當下停下來 grep matrix 是打斷對話 |
| 逐字稿彙整、客戶回饋 | **inbox** | 尚未與 matrix 對帳，無法判定 BUG／SPEC_CHANGE／NEW |
| Claude 自查發現、跑測試抓到 | 判斷完成 → **backlog** | 發現當下就在讀那份 code，對帳成本近乎零 |
| wave grill 未涵蓋的決策 | 判斷完成 → **backlog** | grill 過程已經釐清規模與影響面 |
| 另一個 session 主動加的工作 | 判斷完成 → **backlog** | 它有時間做完整判斷，不需要繞一圈 |
| wave 收尾的 ERRATA 升級候選（`from: errata:*`） | **inbox** | 走專屬判定（見 4.5），不套 type／flow 判斷樹 |

直接寫 backlog 時，仍要走完步驟 1–4 的判斷（只是省掉「先落 inbox 再回頭處理」那一趟），並在 frontmatter 的 `from` 欄註明來源（例：`from: "自查（wave-intake-kit 執行中）"`）。

**backlog 檔案格式**（frontmatter + body）：
```yaml
---
id: B-NNN
type: BUG           # BUG | NEW | CHORE | SPEC_CHANGE
pri: P2             # P0..P4
flow: spec          # direct | spec
status: "ready"     # ready | done:<wave-id> | dropped:<理由> | ⚠️需客戶確認 | orphan-review
matrix: "—"         # RTM 條目或 —
closed: 2026-07-29  # done/dropped 時寫入日期（ready 不填）
from: "INB-112"
touches:            # status=ready 必填
  - apps/web/src/server/api/routers/xxx.ts
created: 2026-07-29
---
## evidence
（敘事）
## proof
（done/dropped 必填——commit hash／實跑輸出）
## notes
（其餘）
```

**判斷不完整就不要硬填**——填錯的 `flow` 會讓大改動溜進 `direct` 而略過設計階段，比多繞一趟 inbox 貴得多。

## 0.5 四個從實務長出來的欄位（2026-07-25 起吸收自既有波產出慣例）

| 欄位／值 | 用途 |
|---|---|
| `proof`（`done` 必填） | 「已完成」必須可查證：commit hash／實測輸出／counter 變化／閘門結果。**填不出來就不能標 done** |
| `🔶止血:{wave-id}` | 症狀已緩解、根因仍在。**不可視同完成**——它會在別處以別的樣貌再出現 |
| `pri: P0` | **本波製造的回歸**。自己造的債優先於一切既有待辦，因為那是淨新增的傷害 |
| `touches`（`ready` 必填） | 預計寫入的 repo-root-relative exact path 或 glob，供 `/wave batch` 在開波前做交集預警 |

## 1. 定位規格條目

```bash
grep -rn "<關鍵詞>" <spec_layer>
```

- 0 筆命中 → 改用 `impl_routes` / `impl_details` 欄位再找一次（路由名、檔名）
- 仍 0 筆 → `type: NEW`，`matrix: （待新增條目）`
- ≥1 筆 → 讀該條 `detail_specs`，進入步驟 2

**`spec_layer` 為空（config 未設）** → 跳過本步與步驟 2，直接進步驟 3；`type` 僅可為 `BUG` / `NEW` / `CHORE`，且必須在 triage 輸出明示「已降級：本專案未設 spec_layer，未做規格對帳」。

## 2. 三分類判定

比對「使用者描述的期望行為」與「`detail_specs` 記載的行為」：

| 情況 | 判定 |
|---|---|
| specs 有寫，程式碼不符 | `BUG`（matrix 不動） |
| specs 有寫，程式碼符合，使用者想改 | `SPEC_CHANGE` ⚠️ |
| specs 未涵蓋此面向，但 RFP `rfp_text` 隱含 | `BUG`（順帶補 detail_specs） |
| specs 未涵蓋，RFP 亦無 | `NEW`（matrix 加 status: planned） |
| 與 `rfp_text` 字面衝突 | `SPEC_CHANGE` ⚠️⚠️ 標「影響驗收」 |
| 使用者要求的是內部改善（重構、清理、效能優化、測試補強），不改對外可觀察行為 | `CHORE`（matrix 填 —） |

判為 `SPEC_CHANGE` 者，`status` 一律先填 `⚠️需客戶確認`，不得直接填 `ready`。

## 3. 去重

與 `backlog/` 目錄既有 B-NNN.md 比對（同 matrix 條目 + 語意相近）→ 命中則併入既有檔的 `from` 欄，不新增條目。查詢用 `bash ~/projects/skills/kit/tools/backlog-ls.sh --status ready` 或 `grep -al` 掃 frontmatter。

## 4. 分流判定（flow 欄位）

**以下任一成立即 `flow: spec`，與 type、status 皆無關：**
- 預估動 4 個以上檔案
- 含架構或資料模型決策
- 跨模組

**以上皆不成立 → `flow: direct`。**

三個欄位正交，不可互相推導：
- `type` 決定規格層影響（是否動 matrix），不決定 flow
- `status` 決定能否排波（`⚠️需客戶確認` 的項 wave 取不到），不決定 flow
- `flow` 只衡量工作量規模

例：一個 SPEC_CHANGE 若只改一個預設值，是 `type: SPEC_CHANGE`＋`status: ⚠️需客戶確認`＋`flow: direct` ——客戶確認過後直接進 wave 做掉，不需要寫 spec。一個 BUG 若要動 5 個檔並改資料模型，是 `type: BUG`＋`flow: spec`。

`flow: direct` 的工作項**不需要**先走 brainstorming。這不是在合理化跳過流程——分流判定已在 triage 階段完成，重複 brainstorming 只會產生無人閱讀的 spec 並加劇文件堆積。

### 4.1 `touches` 填寫與交集預警

每筆 `status: ready` 的 backlog 檔 frontmatter 都必須有 `touches:` 欄位。值是預計會寫入的檔案，
不是只讀的參考資料：

- 已知單一檔案時填 repo root 起算的 exact path，例如
  `apps/web/src/server/api/routers/case.ts`。
- 同一窄目錄內有多個尚未定名的檔案時可填 glob，例如
  `apps/web/src/components/case-work-wizard/**`；不得只填 `src/**`、`docs/**`
  這類失去排程價值的寬泛範圍。
- 有多個範圍時用全形分號 `；` 分隔，每個 path/glob 都各自用反引號包住。
- 規劃尚未收斂、無法安全判斷時填 `unknown:<具體原因>`，例如
  `unknown:尚待 spec 決定資料模型`。不得猜路徑，也不得只寫裸 `unknown`。

`/wave batch` 排出候選工作後，必須在產生 wave prompt 前逐對比 `touches`：

1. exact path 相同，或任一 exact path 被另一方 glob 涵蓋，視為確定交集。
2. 兩個 glob 有共同可匹配路徑時也視為確定交集；列出工作項 id 與相交 pattern，
   發出「交集預警」，不得排進同一波或並行波。
3. 任一方含 `unknown:<具體原因>`，視為與所有項目交集未明；發出未決預警，
   先在規劃階段把它收斂成 path/glob，未收斂前不得並行。
4. 比對只決定排程衝突，不取代開工後以 `wave-registry.sh intersect` 對實際 diff
   的二次檢查。

## 4.5 ERRATA 升級判定（`from: errata:*` 專用）

wave ledger 的 ERRATA 條目在 `wave-close.sh` 之後就不存在了，且它的回灌機制只覆蓋
Subagent-Driven 的心跳 prompt——Inline 執行、compaction 後、下一波都讀不到。收尾時
帶著三問的判定結果落到 inbox，triage 在此決定最終落點。

**這些項不套步驟 1–4 的 type／flow 判斷樹**（教訓不是規格條目，對不到 matrix），直接走下表：

| 判定 | 落點 | 動作 |
|---|---|---|
| 補 gate（收尾 Q2 判為機器可擋） | `backlog/B-NNN.md` | `type: CHORE`＋`flow` 照規模判；evidence 寫清楚擋什麼、擋在哪一層 |
| 升級候選: CLAUDE.md（收尾 Q1+Q3 全過） | 專案 `CLAUDE.md` | 見下方收錄規則 |
| 收尾未附判定結果 | — | 退回：在 inbox 標 `status: ⚠️缺判定`，要求補三問結果再處理，**不代為判斷** |

### 收錄進 CLAUDE.md 的規則

**不開固定 ERRATA 區段。** 寫進主題最近的既有段落（Shell 操作類寫進操作鐵則、測試類寫進
測試策略），沒有對得上的段落才新開——固定空間會誘發填空衝動，且 CLAUDE.md 每個 session
都要載入，只增不減必然劣化成噪音。

每條收錄必須具備，缺一不收：

1. **日期**（`YYYY-MM-DD`）與**具體案例**（哪個波、什麼操作、錯成什麼樣）
2. **違反後果**——讀者要知道代價才會遵守，「請注意 X」沒有約束力
3. **可執行的正確做法**——不是「要小心」，是「改用 `$queryRaw(Prisma.sql\`…\`)`」

**加一減一：** 每收一條，同時檢查同段落有無已失效的舊條（機制已改、工具已換、連續三個月沒
再犯的一次性教訓）→ 有就刪，並在 triage 摘要列出刪除項。CLAUDE.md 沒有行數硬閘門，這條
是唯一的收縮力。

## 5. 非回饋內容

除錯對話、技術問答等誤收項 → `status: dropped:{理由}`，保留紀錄不刪行（供日後調整詞庫）。

## 6. 收尾

- 已處理的 `INB-NNN` 從 `inbox.md` 移除（其內容已轉入 `backlog/B-NNN.md` 的 `from` 欄）
- **移除條目後必須更新檔內 high-water mark**：`<!-- INB-seq: NNN -->`（NNN＝本批最大編號）
  ——`kit_next_id` 靠它在條目清空後仍接續編號，漏寫＝下一筆從 001 起與 git history 撞號
  （2026-07-28 dfaa 實見）。註記放檔頭歷史指標區，每批 triage 更新為新最大值
- 輸出處理摘要：新增 N 筆、併入 M 筆、dropped K 筆、⚠️ 待確認 J 筆
- **若 config 已設 `spec_check` 且本批有任何 `type: SPEC_CHANGE` 或 `NEW` 的項目**（會動到規格層），輸出提醒使用者執行該指令驗證規格檔一致性。若 `spec_check` 為空則跳過此提醒。

## 7. 逃逸歸因 enum（`--from` 回饋批次波 triage 專用——與上述 INB/backlog 判斷樹是不同機制，不套用步驟 1–6）

> 依據：存在性只量「防線有沒有蓋到」，有效性要量「防線真的攔到沒有」。逃逸缺陷（客戶回報
> bug／驗收台 issue）能歸因到「本該攔住卻沒攔住」的具體防線，是下一輪 roadmap 排波優先序的
> 直接證據；欄位成本低（每 issue 約 10 秒），換到的是把「感覺哪裡弱」變成可累積、可統計的事實。

**填寫時機**：`/wave --from` 回饋批次波 Phase 2 掃描／triage 每筆項目時，在 triage 表加一欄
「該攔防線」——搭現有 triage 步驟的便車，不另立獨立流程。

**值域（closed enum，六選一，不可空白、不可複選）**：

| 值 | 意涵 |
|---|---|
| `lint` | ESLint custom rule／ratchet counter 本該擋下 |
| `gate` | pre-commit／pre-push hook（`gates.d/` 或專案既有 gate）本該擋下 |
| `quality-check` | 資料正確性對帳機制（db-count／db-assertion／db-ratio／truth-match 類）本該抓到 |
| `E2E` | acceptance E2E 本該覆蓋這條 user flow，但沒對應 spec 或 spec 沒測到這個分支 |
| `flow-check` | 流程／狀態機／查詢行為對帳機制本該對帳到這個查詢／流程行為 |
| `none` | 目前沒有任何防線覆蓋此類問題——**唯一會直接產生新工作項的值** |

- **quality-check vs flow-check 難分時**：資料正確性（欄位值、計數、聚合）算 `quality-check`；
  流程／狀態機／查詢行為對帳算 `flow-check`。真的模稜兩可 → 歸 `quality-check`（既有覆蓋率
  較高，避免同一逃逸被雙重計數）
- **選值原則**：選「設計上原本最應該攔住」的第一道防線，不是「理論上也可能攔到」的全部——
  其餘防線的關聯落差在 triage 表 notes 欄補述，不塞進本欄
- **`none` 的額外要求**：值為 `none` 時，notes 必須附「新防線候選」的具體方案雛形（哪類
  rule／gate／check、大致怎麼做），否則不算完成歸因——避免 `none` 變成不了了之的垃圾桶分類
- **消費者**：若專案已裝 `governance-health` 模組，彙整跨波次逃逸歸因分布 → 下一輪 roadmap
  排波優先序輸入（哪道防線漏最多＝下一波優先修的防線）
- **明確不做**：不建攔截即時留痕 log（想不出消費者前不建）；本欄只在事後 triage 時人工標記
  一次，不追蹤攔截當下的即時行為

> 各專案的具體防線名稱不同（`gate` 對應各自的 `gates.d/` 或既有 pre-commit hook；
> `quality-check`／`flow-check` 對應各自的資料／流程對帳機制），但 enum 值域本身通用。
> 各專案的 quality-gates 文件應引用本節作為 source of truth，只在本節之外補充該專案的
> 具體防線名稱對應表，不重複定義值域與規則本身。
