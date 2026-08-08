---
name: wave
description: 規劃並啟動一波開發波次（純開發引擎）。適用於：開始一輪多工作項的開發、從 requirements 或回饋批次排工作、查看或放棄進行中的波。觸發詞：/wave、開新波、新一波、plan wave、啟動開發；子指令 /wave batch（讀 backlog 批次規劃多波、產全部 wave prompt）、/wave status、/wave drop {id}。
argument-hint: "（選填）逐字稿路徑、會議檔案、或簡述這波方向"
---

# Wave — 開發波次規劃與啟動

> **本版為精簡實驗版（2026-07-25）**：拿掉五角度合約強制清單、REUSE/TWINS/INTENT/AUTH 強制標記、
> 無條件 grill、E2E 七步強制清單（各自的 commit 有完整說明），測試 Opus 5 自行推進工作的能力。
> 完整版見 git 歷史 `f5a302e`（`git show f5a302e:wave/SKILL.md`）。品質下降即還原。

**Wave 是純開發引擎。** 非開發批次工作（文件整理、信件處理等）不用 wave，回歸普通 session＋todo——那些工作不需要 worktree／驗證合約／goal condition 這套重裝備。

## Core Principles

- **Wave 是唯一入口。** 使用者不需要記「要不要先 align」、「要不要看 requirements」——Wave 自動判斷並串接。
- **一波帶走。** 所有掃出的未完成項都排進這一波，不建議延後。遇到真正的 blocker 在該項旁邊標註原因讓使用者決定，但不主動歸類為「建議延後」。
- **範圍完整性不變量（全域，規劃期與執行期皆適用）。** 所有掃出的未完成項排進本波。工作量超出預期 → 排 Checkpoint 分段後開工。範圍縮減唯一合法路徑：**使用者主動提出**。session 時長與 context 都不是縮範圍的理由（見長跑規範第 3 條）。
- **唯一停點制。** 全流程僅兩個合法停點，其餘階段轉換與項間一律自動接續——不停、不問、不結束 turn。詳見「停點規則」。
- **品質不入 skill。** Wave 對「merge 前品質」唯一認識的概念＝typecheck 的 exit code（~90 秒，同步）。完整品質由 merge 後的 deep lane 承擔——supervisor 每 3 個 merge 跑一次完整 `wave-gate.sh baseline`，紅燈自動開 issue，進 pctl dispatch 迴路修復。任何新的品質檢查需求一律寫進專案的 gate script／hook／lint（deep lane 會跑到），不得加進本 skill 的流程條文——skill checklist 是規則的暫存區，機器化後即刪。
- **零模式判斷。** 本 skill 無模式偵測、無模式分支——LLM 的模式判斷是 drift 源。輸入來源固定為 Phase 2 四來源掃描（backlog 即來源 1），管線永遠同一條。

## 停點規則（唯一停點制）

> **CRITICAL: 全流程僅有兩個合法停點。除此之外不停下等待輸入、不問「要不要繼續」、不結束 turn。**

**合法停點：**

1. **Phase 0 Align 問題**——「這波有新素材要帶入嗎？」（`/wave` 帶參數時跳過，此時全程零規劃停點；**無參數時必問，不可自答「沒有素材」代跳**）
2. **Phase 4 範圍確認**——工作清單 + UX 審計清單 + 交集預警一次問完（執行方式不問，自動採用——見 Phase 4「執行方式自動採用」）

**停點提問形式：** 環境有 `AskUserQuestion` 工具時，兩個停點的提問用它結構化呈現——Align 用固定三選項；Phase 4 用「UX 審計清單」multiSelect（工作清單本體仍以文字完整列出，選項只承載決策）。無此工具則文字問答。

**自動接續（不停、不問、不結束 turn）：**

- Phase 1 → 2 → 2.5 → 3
- Phase 4 確認後 → Phase 5 產出 → Phase 6 建 worktree → 設 goal → 開工
- 執行期項與項之間
- typecheck → merge

**Turn 結束前自檢：** 結束 turn 前檢查最後一段輸出——若是計畫、問題、下一步清單、或「我接下來會…」的承諾 → 立刻用 tool call 做掉，不准就此結束 turn。（本節所列合法停點與例外的提問不在此限。）

**Phase 2.5 例外：** brainstorming / grill 是本來就需要人的訪談，不算違規停點，但完成後自動回到 Phase 3，不重新等指令。

**合併協助例外：** merge 回 main 時遇到改法矛盾衝突需使用者裁定（見 `references/multi-wave.md`「合併協助」節）——那發生在 wave 完成後的合併階段，且屬破壞性裁定，不受本節限制。

**破壞性操作確認例外：** 長跑規範第 1 條要求確認的破壞性操作（刪除、覆寫、重設）屬合法停點。

**需人裁定例外：** 執行期遇到需人裁定的事項，按「長跑行為規範」第 5 條非阻塞升級處理——僅當其阻塞所有剩餘工作時才停下。

## Dispatched 模式（`PORTFOLIO_DISPATCHED=1`）

> Portfolio supervisor 無人派發的波（env 由 dispatch_cmd 設定）。命中時本節**覆寫**下列條款；未命中（人工互動 wave）全文照舊。細則與依據見 [references/dispatched-mode.md](references/dispatched-mode.md)。實證：B-279/280/283/284 四波四種收法（自 merge 繞過 diff 分流、PENDING 等不在場的人、閒置不退場）。

- **零停點**：兩個合法停點全部跳過（派發 prompt 即 Align 素材；Phase 4 只輸出清單不問，❓ 項採推薦方案並記 inbox）。禁用 AskUserQuestion。
- **wave id 沿用 supervisor**：`{id}` ＝ env `PORTFOLIO_WAVE_ID`，不自產名稱。
- **worktree 沿用當前 cwd**：supervisor 已預建 worktree 並以其為 cwd——Phase 6 Step 1 的建立動作跳過（守衛檢查照做）。
- **收尾＝push branch 即結束**：`git push -u origin <branch>` 後輸出總結、結束 session（executor 以 `claude -p` headless 跑，完工自動退出）。不 merge、不碰 main、不跑收尾流程步驟 5-6 的合併協助與 wave-close——push 後 supervisor 跑 typecheck（~90 秒，同步）→ diff 分流 → auto-merge，worktree 清理也由 supervisor 承擔；完整品質閘門在 merge 後的 deep lane 背景跑（見 dispatched-mode.md）。開發自驗照跑 `wave-gate.sh baseline`。
- **PENDING 禁止留給人**：待人事項一律照 `/issue` 開單（body 註明來源 `dispatched:{id}`）；報告只留摘要與 issue 連結。
- **收尾回寫照做**：dashboard/ledger `git rm`、待使用者事項開 issue，全部併入最後 commit（未 merge 也清——supervisor merge 整個 branch）。

## 相依 Skill 缺席降級

本 skill 依賴的其他 skill：諮詢 `/askfable`；訪談 `/grill-me`、`/grill-with-docs`、`/brainstorm`（三者與 wave 同屬 kit package，正常安裝必在——本條款主要防跨 harness／未安裝環境）；安全 `/insecure-defaults`、`/sharp-edges`、`/semgrep`；UX `/ui-test`、`/wcag-accessibility-audit`、`/nielsen-heuristics-audit`、`/ux-audit-rethink`（安全與 UX 皆為 vendored 外部包）。任一在環境中不存在時，與原生工具 fallback 同 pattern 降級——缺席不得靜默跳過，也不得卡死流程：

- ledger 記一行「無 {skill}，該步降級」；合約/閘門對應步驟標 `SKIPPED(不可用)`，視同「已執行並記錄」過閘（goal condition (3) 的安全/UX 判定同此認定）
- 收尾報告以「品質 caveat」區醒目列出所有 SKIPPED 步驟——降級是誠實揭露，不是豁免
- 訪談類缺席 → 改 inline 訪談（照 Phase 2.5 的聚焦清單逐題問使用者），訪談本身不可跳過——缺的是 skill，不是對齊

## Harness 適配（Codex CLI）

Codex CLI 執行時，**在執行任何 Phase 前**先完整讀取 [references/codex-adaptation.md](references/codex-adaptation.md)。工具名稱需替換；尤其建立 worktree 後必須結束目前 session，從 worktree 目錄重開 Codex。其餘停點、合約與閘門不變。

## Workflow

### Phase 0: 多波偵測 + Align 判斷

**Step 1: 動態重建 Registry**

掃描現有波次狀態（不讀檔，每次動態重建）：

```bash
# 掃 main 的 wave dashboard
ls .claude/dev/wave-*.md 2>/dev/null

# 掃所有 worktree 的 wave dashboard
git worktree list | while read path _; do
  ls "$path/.claude/dev/wave-"*.md 2>/dev/null
done
```

如果有其他 🟢（待啟動）或 🟡（執行中）的波，顯示概覽：

> ## 🌊 現有進行中的波
> | ID | 簡述 | 狀態 | 進度 | 涉及檔案 |
> |---|------|------|------|---------|
> | orders-api | 訂單 API | 🟡 執行中 | 3/5 | src/server/api/routers/order* |

**Step 2: 自動命名本波**

Claude 從工作項方向自動生成 ID（如 `suspect-merge`、`report-ui`），不問使用者。使用者不滿意才改。無其他波在跑時也可用日期 ID（`wave-0630`）。

Dashboard 檔名：`.claude/dev/wave-{id}.md`

**向下相容：** 如果已有舊的 `.claude/dev/wave.md`（單波模式），自動遷移成 `wave-legacy.md`。

**Step 3: Align 判斷**

問使用者一個問題：

> 這波有新素材要帶入嗎？（逐字稿、會議紀錄、客戶回饋、新規格）
> - 有 → 請貼上或告訴我檔案路徑
> - 沒有，從現有 requirements 繼續
> - 我想重新對齊某份舊逐字稿 → 告訴我哪份

如果使用者在 `/wave` 後面直接帶了參數（檔案路徑或文字），跳過這個問題直接進 Phase 1。

**Align 停點的接續動作（收到答案後依序執行）：**

1. 有新素材 → Phase 1 Align 落檔
2. 執行 Phase 2 四來源掃描——**在此之前不得預掃**：Phase 0 只允許 registry 掃描，requirements / TODO / git log 的內容掃描一律在本動作才開跑
3. 掃描收斂 → Phase 2.5 判斷

### Phase 1: Align（有新素材時）

執行簡化版 align：

1. **Digest** — 讀取素材，摘出行為承諾 / 需求變更 / 新決策。素材為逐字稿檔且專案有 `.claude/dev/feature-map.md` 時，先查其 STT 勘誤表校正固定轉錯詞
2. **Ground** — 素材為口語化描述（打字或逐字稿）且專案有 `.claude/dev/feature-map.md` 時，把每個需求 resolve 成 route＋檔案範圍；完整程序（命中驗證／fallback 探索／❓ 集中 Phase 4／靜默累積）讀 `references/hooks-formats.md`「feature-map grounding 程序」節照做
3. **Diff** — 比對專案既有規格文件（如有；路徑因專案而異，未維護規格文件的專案本步全數歸類 🆕）現有內容，分三類：
   - 🆕 新增（既有規格文件沒有的，或專案未維護規格文件）
   - ⚠️ 衝突（與現有描述矛盾）
   - ✅ 一致（已對齊）
4. **確認衝突** — 只有 ⚠️ 項需要使用者裁定（逐條，附推薦方案）
5. **落檔** — 本步驟產出的行為細節不寫外部規格檔案：直接帶入 Phase 2/3，成為對應工作項的描述與合約
   依據，隨 Phase 5 一併寫入 `wave-{id}.md`（比照『輸出 2: Session Context』既有機制）
   - 本條只改 wave 自身「簡化版 align」的落檔目標；CONTEXT.md／ADR 等文件同步不由此步驟涵蓋，不受影響

如果沒有新素材，跳過此 Phase。

### Phase 2: 掃描工作項（loop-until-dry）

> 掃描必須在 Align（Phase 0 Step 3 / Phase 1）**之後**執行——新素材要先落檔 requirements 才掃得到，順序顛倒會掃到舊狀態。Phase 0 不預跑掃描。

**回饋批次不降級：** 不論工作項來自哪個來源（GitHub issue、驗收台 issue、LINE 回報、bug 清單），管線完全相同——驗證合約、🔒 安全步驟、typecheck、goal condition 全部照走，不因「只是小修」降級任何規則。與 CONTEXT.md／requirements 矛盾的項先與使用者裁定，不默默改。

> **CRITICAL: 掃描完備優先於掃描速度。四個來源各掃一輪後再掃一輪，連續兩輪無新工作項才准停。防「掃到夠交差就停」。**

> **⚠️ 硬閘門：** 帶 `blocked:verified`（外部阻塞，含需客戶確認）或 `agent:running`（已有人在做）的
> issue 不得取用排波，即使使用者說「全部做完」。前者需阻塞解除、拿掉 label 後才可取。
>
> **分流：** 取用的 issue 依性質處理——規格明確的直接排成工作項；帶 `needs-design`（規格未定、需設計
> 裁定）的先走 `/brainstorm`（呼應下方 Phase 2.5 加碼判斷）。

自動執行（不問使用者），四個來源：

```bash
# 來源 1：使用者指名要在波裡做的 issue
gh issue list --label hold:wave --state open --limit 50

# 來源 2：程式內待辦標記
grep -rn "TODO\|FIXME" src/ lib/ app/ 2>/dev/null | head -50

# 來源 3：堆在佇列的機器訊號（deep lane 紅燈、巡檢、外部回報）
gh issue list --label signal --state open --limit 50

# 來源 4：git log 近況＋舊 wave 的延後決策（找做一半／曾延後的）
git log --oneline -20
grep -A 20 "📋 延後決策" .claude/dev/wave-*.md 2>/dev/null
```

從四來源收集所有未完成項（🔴 未實作 / 🟡 部分實作 / ❓ 未決 / 舊 wave 檔的延後區塊 / 半成品）。

**Loop-until-dry 規則：** 四來源掃完一輪後，帶著已找到的工作項**再掃一輪**（第二輪常因理解了脈絡而多挖出關聯項）。連續兩輪無新項 → 掃描完成。

**碎片化審計（條件觸發）：** 使用者描述含「風格不一致」「各自做的」「複製貼上漂移」等信號，或工作項本質是「把 N 個獨立實作統一成共用元件」→ 掃描收斂後加派一個 Explore agent 跑 UI 碎片化審計——程序、prompt 模板、地圖格式讀 `references/ui-fragmentation-audit.md` 照做。地圖併入 Phase 3 規劃，不加停點；使用者在 Phase 4 看到完整地圖再做 scope 決定（只修使用者指出的那幾處＝掉進「修一處冒一處」循環）。

> **CRITICAL: 規模與時長脫鉤（見 Core Principles「範圍完整性不變量」）。真 blocker 在該項旁標註原因交使用者裁定。**

**交集分析（多波時）：** 如果 Phase 0 偵測到其他進行中的波，跑 `bash <kit>/scripts/wave-registry.sh intersect`——它對每對活躍 worktree 以 `git diff --name-only <base>...HEAD` 算實際改動交集，並用 merge-tree 預演分級（可自動合併／需裁定）。本波尚未建 worktree 時，把本波工作項預期動到的檔案與 `intersect` 列出的他波改動集人工對照。結果記錄下來，Phase 4 顯示預警。

### Phase 2.5: 判斷是否需要訪談（grill / brainstorming）

**觸發訪談的訊號（命中任一即觸發）：**
- 工作項含 ❓ 未決項（Phase 2 掃出）
- ≥2 個有效做法且選擇不可逆（架構或 UX 決策）
- 描述模糊到無法寫出具體合約
- 與 CONTEXT.md / ADR 既有共識矛盾
- 新功能或從零開始的模組（無既有程式碼可參照）

**不觸發：** 明確 bug fix 批次、行為不變的重構。

**Skill 選擇：** 方向未定 → `/brainstorm`；已有方案要壓力測試 → `/grill-me`；牽涉 CONTEXT.md／ADR 同步 → `/grill-with-docs`。需要 brainstorming 時先 brainstorming 再 grill。碎片化統一項 → `/brainstorm` 直接呈現淺/中/深光譜（`references/ui-fragmentation-audit.md`）。

完成後帶著結論進 Phase 3，結論直接影響合約的覆蓋場景設計。

### Phase 3: 分類、排序、寫驗證合約

> **CRITICAL: 每個工作項在規劃階段就必須寫好驗證合約——具體的指令 + 預期輸出。執行時按合約跑，不是自由心證。**

所有工作項一律 🤖（Claude 獨立完成 + 自驗），並為每項寫驗證合約：

**🤖 自主可完成（Claude 獨立完成 + 自驗）：**
- 後端邏輯（API、計算、資料處理）→ 單元測試 + 整合測試
- UI 功能 → Playwright E2E 自動驗證（導航→操作→結果斷言）
- Bug fix → 先寫重現測試再修
- UX 流程 → Playwright 跑完整操作流程，斷言功能正確
- 視覺/排版 → Playwright 截圖自檢（預設＋最大字級各一張、空資料態），確認元素存在、佈局不破版、文字不重疊不溢位；**純樣式項不寫 unit test**（Smart TDD：UI styling 不需 TDD——截圖驗證取代）

#### 驗證合約格式

每個工作項必須在規劃階段附帶驗證合約。合約 = 可執行的指令 + 預期輸出 + 覆蓋場景。首次寫合約前讀 `references/contract-examples.md` 對照五個範例（含資料守恆/規模場景寫法）。

#### 安全 Skill 合約規則（🔒 標記步驟）

依工作項性質，在驗證合約中自動加入安全審計步驟：

| 工作項性質 | 自動加入的安全 skill |
|-----------|---------------------|
| API route / tRPC router / middleware | `/insecure-defaults` + `/sharp-edges` |
| Auth / 權限 / session / crypto | 三個全開（含 `/semgrep`） |
| 新增 dependency / config 變更 | `/insecure-defaults` |
| 任何 `.ts/.tsx` 程式碼變更 | `/semgrep`（semgrep baseline） |

**🔒 步驟的效力：**
- high / critical findings → **blocking**，必須修到 0 才能 commit
- medium / low findings → 記錄到 wave-{id}.md「🔒 安全審計結果」區塊，不阻擋 commit

**合約寫法規則：**
- 指令必須是可複製貼上直接跑的（含完整路徑）
- 預期輸出寫具體（`≥3 tests passed`，不是 `tests pass`）
- 覆蓋場景自己判斷該驗什麼——happy path／edge case／誤用／資料守恆對帳／生產規模等角度視工作項性質取捨（資料管線類想想對帳與冪等、資料量敏感 UI 想想生產規模），合約列了的就要全跑
- `quality-gates.md` 存在時：鉤子檔「Gate 指令」表中觸發條件命中的指令，注入對應工作項合約（例：動到 parser → 該項合約加一條 `pnpm quality:affected --run`）
- `intake.config.yaml` 的 `spec_layer` 非空（專案有 RTM）時：每個工作項必帶 `matrix` 欄——對應 matrix 條目 ref 或 `none(理由)`，格式與傳遞機制見 `references/templates.md` Dashboard 模板的 matrix 欄說明
- 碎片化統一項照 `references/ui-fragmentation-audit.md`「共用殼工作項 pattern」寫：每殼一個工作項；合約＝typecheck＋既有測試全綠＋一致性截圖自檢＋空資料態，**不新寫 unit test**（純換殼行為不變）
- Bug fix 的孿生掃描（同錯誤模式全案搜尋）、UI 項的重用盤點（重用優先於新建，紀律見 `references/ui-fragmentation-audit.md`「元件重用紀律」節）——照做，但 `TWINS:`／`REUSE:` 標記需要時才寫，不再是合約完整性的必填欄

排序原則：先做有測試可驗的後端邏輯 → 再做 Playwright 可驗的 UI 功能 → 依賴關係決定其餘順序。

#### Grill/Spec 決策審計（有訪談產出時必做）

> **CRITICAL: 分類完工作項後，必須回頭比對 grill/brainstorming 產出的所有決策。沒有對應工作項的決策必須明確落到收件匣，不得消失在對話裡。**

1. **收集決策源** — 讀取 Phase 2.5 的 grill/brainstorming 紀錄（spec 文件、grill 對話中的共識）
2. **逐條比對** — 每個決策是否有對應的工作項（🤖）
3. **未涵蓋的開成 issue（先過可解性檢查——開單不是緩衝墊）** — 沒有對應工作項的決策，先問「本波真的不能做嗎」：能做（無外部 blocker、規模可吸收）→ 排進本波工作項，不開單。只有**驗證過的真 blocker**（外部依賴不可得、需客戶 async 確認、依賴未 merge 的他波、使用者明裁延後）才照 `/issue` 開單，掛 `blocked:verified`＋`hold:wave`，body 記錄：
   - 決策內容一句話 ＋ **為何本波不能**（具體 blocker，「不順路」「先記著」不是理由）
   - 來源：`grill:{spec 哪段或哪題}`
   阻塞解除、拿掉 `blocked:verified` 後，下一次開波即被來源 1 掃到，不需要 wave 自己維護一張表。
4. **零未涵蓋也要寫** — 如果所有決策都有對應工作項，明確寫「本波涵蓋所有 grill/spec 決策」

**進入 Phase 4 前**，若 `/askfable` 可用，先執行 [references/fable-consultation.md](references/fable-consultation.md) 諮詢點 1（獨立檢查漏項、合約覆蓋與排序）；發現缺口先修正再呈現。

### Phase 4: 向使用者確認範圍

輸出工作清單前先讀 `references/templates.md` 的「Phase 4 工作範圍輸出範本」節，照範本格式問使用者（驗證合約逐項列出、預估規模、Checkpoint 分段、執行方式自動採用結果一併呈現）。

如果這波有前端工作項，在工作清單後面多輸出 UX 審計推薦（規則表見下方）。

**UX 審計推薦規則：**

| 工作項性質 | 推薦的 UX skill |
|-----------|----------------|
| 新頁面 / 整頁改版 / 大量新互動面 | `/ui-test`（探索性對抗測試；**須跑在真實規模資料**，優先用 quality-gates.md 大規模資料 smoke 清單） |
| 新增表單 / 互動元件 / 導航變更 | `/wcag-accessibility-audit` |
| 新頁面 / 新流程 / 新 layout | `/nielsen-heuristics-audit` |
| 整頁重設計 / 大量 UX 改版 | `/ux-audit-rethink` |

> `/ui-test` 不再對「任何前端工作項」必推——blocking 級把關已由 UI 項的 Playwright 自驗承擔（見「E2E 驗證責任制」）。ui-test 的定位是探索性掃描，只在新增大量 UI 面時值得跑；一般修改波不排它，跳過不需寫理由。

**檔案交集預警（多波時）：** 只在**規劃階段**（本 Phase）顯示一次。以 `bash <kit>/scripts/wave-registry.sh intersect` 的輸出為準——只列它標「⚠️ 需裁定」的檔（exit 1 ＝ 有需裁定交集），標「可自動合併」的不列：

> ## ⚠️ 檔案交集預警
>
> | 檔案 | 與哪波重疊 | 該波狀態 | 分級理由 |
> |------|-----------|---------|---------|
> | prisma/schema.prisma | orders-api | 🟡 執行中 | merge-tree 衝突——同段邏輯 |
>
> 本波將在獨立 worktree 中執行，合併時 Claude 會協助處理衝突。

不阻擋，純資訊。`intersect` exit 0（無需裁定交集）時不顯示。

分級判準（腳本內建，判準＝「merge 時需不需要使用者裁定改法」）：append-only 檔（`wave-INDEX.md`、ledger、inbox）與「兩邊各自加行／各自新增獨立區塊」（merge-tree 預演可自動合，或衝突但兩邊皆純加行）標可自動合併；同一行／同段邏輯衝突、兩邊各自新建同名檔標需裁定。

> **CRITICAL: 執行期不主動報交集。** Phase 4 之後、直到收尾為止，**不因為讀到某個檔就回頭提「這裡可能跟別的波衝突」**。使用者的原話：「你會幫我處理 merge，但有時候是你自己發現有衝突提早在講」——那類提醒時機隨機、資訊零碎、且多數是假警報（實測：現存唯一交集是 `wave-INDEX.md`，merge-tree 顯示 41 處衝突，但兩邊都是純 append，三秒可解）。
>
> 唯一例外：判斷「merge 時我自己解不掉、需使用者裁定改法」——那才提，且要一次講完（哪個檔、兩邊各自的意圖、為何無法自動合併）。

**❓/需裁定項的處理（必做）：** 掃描出的每個 ❓ 未決項、以及 Phase 1 Ground 對不到的每個 ❓ 項，必須做成 Phase 4 AskUserQuestion 的**獨立問題**（選項 = 各方案／最似位置推測，推薦方案標 Recommended）——使用者就在停點上，裁定成本最低。Grounding ❓ 項裁定後立即把確認的對應 append 回 `feature-map.md` 別名欄。範圍完整性不變量適用（見 Core Principles），此處另加「待裁定後可追加」。使用者裁定 → 該項排入本波；使用者明選「延後」→ 才照 `/issue` 開單（掛 `hold:wave`，body 註明來源 `grill:{題目}`）。不得由 Claude 自行決定延後。

**執行方式自動採用（不問使用者）：** 固定採 Subagent-Driven（模板既定）。認為 Inline 更適合本波時，必須附一句具體理由（例：項間強依賴無法並行）並記入 dashboard Metadata——仍不問，在 Phase 4 輸出中呈現採用結果即可，使用者不滿意會自己改（2026-07-26 使用者原話：「不需要問我是要 subagent 還是 inline，直接照建議的即可」）。

使用者確認工作範圍 + UX 審計清單後進入 Phase 5。

### Phase 5: 產出三份輸出

#### 輸出 1: `.claude/dev/wave-{id}.md`（Living Dashboard）

產出前先讀 `references/templates.md` 的「Dashboard 模板」節照填。

#### 輸出 2: Session Context（寫入 wave-{id}.md 備查，不需要使用者複製）

Wave 規劃過程中 Claude 已經擁有完整脈絡（工作項、合約、決策、相關檔案），不需要輸出一份 session prompt 讓使用者複製貼上。改為：

1. 把關鍵脈絡摘要寫入 `wave-{id}.md` 的 Metadata 區（供中斷恢復用）
2. 多波時額外記錄並行規則到 Metadata：

```markdown
## Metadata
- **涉及檔案/目錄**: [目錄 glob 清單]
- **並行波**: [其他波 ID + 狀態]
- **並行規則**: 只碰 wave-{id}.md，不動 [列出其他波涉及檔案]
```

#### 輸出 3: Goal Condition（Claude 自動設定）

遵循 goal condition 五原則：
- 可觀測、可驗證、有範圍、有約束、簡短

> **CRITICAL: goal condition 必須寫入 wave-{id}.md 的「🎯 Goal Condition」區塊。/goal 是使用者的 CLI 指令，Claude 無法自行執行——使用者有下 /goal 就同步，沒下也以 dashboard 區塊為準，收尾時逐條自核。**

**格式：** 照 `references/templates.md`「Goal Condition 模板」節逐字填入（七條＋約束），{id} 與約束代入本波實值。

### Phase 6: 建立 Worktree → 開工

> **CRITICAL: 規劃完直接在本 session 開工。**

> **CRITICAL: 所有 wave 一律在獨立 worktree 中執行，不在 main 工作。無例外。不管是單波還是多波、不管專案大小、不管工作項多少。這是硬性規則，不是建議。**

**Step 1: 建立 Worktree（開工前的強制動作）**

> **Dispatched 模式**：supervisor 已預建 worktree 且 cwd 就在其中——跳過本 Step 的建立動作（守衛檢查照做），wave id 用 `$PORTFOLIO_WAVE_ID`，直接從「Gitignore 防護」接續。

**工具載入**：deferred-tool 環境先 `ToolSearch select:EnterWorktree,ExitWorktree,TaskCreate,TaskUpdate,ScheduleWakeup,SendMessage` 一次載齊本 skill 用到的原生工具（查無者視為環境不提供，走各條款的 fallback）。

在輸出啟動宣告之前，先建立 worktree。**優先用原生工具**：環境有 `EnterWorktree` 工具時，直接 `EnterWorktree({ name: "wave-{id}" })`——harness 建立並追蹤 worktree，cwd 不會漂移（原生工具的 branch 命名由 harness 決定，如 `worktree-wave-{id}`，與手動流程的 `wave/{id}` 視同等效）。

無原生工具時 fallback 手動流程：

```bash
# 建立 wave branch + worktree
git branch wave/{id} 2>/dev/null || true
git worktree add .claude/worktrees/wave-{id} wave/{id}
cd .claude/worktrees/wave-{id}
```

> ⚠️ **守衛檢查（手動流程必做；原生工具建立後做一次確認即可）：在 worktree 內執行 `git rev-parse --show-toplevel`，確認輸出路徑包含 `worktrees/wave-{id}`。不在 worktree 內就停下來，不往下走。**

把 Phase 5 產出的 `.claude/dev/wave-{id}.md` 寫入 worktree（不是 main），同時建立 `.claude/dev/wave-{id}-ledger.md`（格式見「狀態外部化」節）。

**Gitignore 防護（建 worktree 後立即檢查）：** 專案 `.gitignore` 必須含 `.claude/worktrees/` 與 `.superpowers/` 兩條——缺哪條補哪條，隨本波首個 commit 進版控。防止 worktree（embedded git repo）與 SDD scratch 被 `git add -A` 吃進 git。註：`wave-{id}.md` 與 ledger **刻意不 ignore**——下波掃描延後決策、多波 registry、中斷接手都依賴它們在版控內。

**開工序列（worktree 建好後依序執行，每步缺一不可）：**

1. **基線綠燈**——專案有 `scripts/hooks/wave-gate.sh` 時，跑 `bash scripts/hooks/wave-gate.sh baseline` 當基線（涵蓋測試／typecheck／專案自定 gate，輸出帶唯一標記字串確認是本輪跑出的）；無 gate script 的專案跑一次現有測試基線。結果記進 ledger 第一行。之後任何紅燈都可歸因是本波引入還是既存問題——上波遺留的污染在開工時現形，不是 merge 後 deep lane 才發現
2. **Task 系統鏡像**——把工作項逐項 `TaskCreate`（subject = 項名，description 含合約要點），執行中用 `TaskUpdate` 推進 in_progress / completed——使用者在 UI 上看得到的即時進度層。Dashboard + ledger 仍是唯一 source of truth（版控、跨 session 持久），不一致以 dashboard 為準。環境無 TaskCreate 工具才可跳過，且須在 ledger 記一行「無 Task 工具，跳過鏡像」
3. **輸出啟動宣告（Step 2）→ 直接開始第一個工作項**

**Step 2: 宣告後直接開工（不停）**

執行方式已在 Phase 4 自動採用。照 `references/templates.md`「啟動宣告模板」節輸出啟動宣告（有並行波時附並行波清單），然後**直接進入 Step 3，不等待回覆**。

**Step 3: 開工**

兩種方式都先確認 goal condition 已寫入 wave-{id}.md「🎯 Goal Condition」區塊（使用者若下 /goal 則同步，沒下也以此區塊為準），再依 Phase 4 自動採用的方式執行：

**選 1 — Subagent-Driven（第一次派工前先完整讀取 [references/subagent-protocol.md](references/subagent-protocol.md)）：**
1. 每一批派工＝三連動作：① 備 brief（分級規則見該檔「Brief-driven 派工」）② 派 implementer（背景、帶 model tier）③ **立即排 ScheduleWakeup fallback**（delay 分層見該檔「心跳 fallback」；環境無此工具才可跳過，且在 ledger 記一行「無 ScheduleWakeup，跳過心跳」）
2. 每個 subagent 完成一項後回報，controller 親自重跑合約 review（不採信報告文字）
3. 全部完成後跑品質閘門 + 收尾流程

**選 2 — Inline Execution：**
1. 按工作項排序逐項執行（遵循執行泵行為規範）
2. 每項 commit 後更新 wave-{id}.md
3. 全部完成後跑品質閘門 + 收尾流程

兩種方式都遵循同一套執行泵行為規範（見下方），差別只在並行度。**所有檔案操作都在 worktree 內進行。**

---

## 執行泵的行為規範

以下規則在 /goal 執行時 Claude 自動遵循（無論 Subagent-Driven 或 Inline Execution）：

### Worktree 守衛（每次執行動作前）

> **CRITICAL: 寫任何檔案之前，確認 cwd 在 worktree 內。**

```bash
# 守衛檢查——不在 worktree 就停
[[ "$(git rev-parse --show-toplevel)" == *worktrees/wave-* ]] || { echo "ERROR: 不在 worktree 內，停止執行"; exit 1; }
```

如果發現自己在 main 工作目錄而非 worktree，**立即停下**，先執行 Phase 6 Step 1 建立 worktree 再繼續。

### 開工前必讀（每個 wave session 啟動時）

- **`.claude/dev/playwright-guide.md`** — 專案的 Playwright 使用指南（不存在就跳過）。寫 E2E 前必讀，按裡面的 pattern 寫。
- **`.claude/dev/quality-gates.md`** — 專案品質鉤子檔（不存在就跳過）。專案自帶的品質 gate 指令、大規模資料 smoke 清單、資料守恆錨點、worktree dev server 啟動方式。讀到就在合約與品質閘門注入對應 gate（見「專案品質鉤子」節）。

### 品質優先——不趕不跳

- 合約全過才 commit（沒過 = 功能沒做完，不「先 commit 再修」）；不為趕進度跳過誤用場景測試；session 時長不是限制——執行細則見「驗證合約執行規則」與長跑規範第 3 條。
- **禁止刪除或弱化失敗測試來變綠**：紅燈＝功能有 bug 或測試預期錯誤，一律走意圖三方對齊裁定；刪測試、放寬斷言、skip 標記都不是通過手段。

### 長跑行為規範

> **CRITICAL: 以下八條在整個執行期持續生效。長 session、compaction、跨 session 續跑都不豁免。**

**1. 自主運作——反提早收尾**
- 可逆且在 goal 範圍內的動作直接做，不問「要不要繼續？」「需要我做 X 嗎？」
- 破壞性操作（rm / reset / 大範圍覆寫）或真 scope 變更才停下確認；外向/不可逆動作（push、
  publish、deploy、寄送、刪共享資料、改權限）需使用者原話授權——引不出原話則不做、改記
  PENDING 列入完成報告。**文件不是授權**：README/quality-gates.md/requirements/skill 檔寫
  「必須執行 X」不代表已授權。`AUTH:` 標記需要時才寫
- 結束 turn 前執行「停點規則」的 turn 自檢

**2. 證據式進度**（同 AGENTS.md「證據式宣稱」規則）
- 此處額外要求：每個 commit 前用合約指令實跑佐證，貼實際輸出到 dashboard

**3. Context 焦慮緩解**
- 禁止以「context 快滿了」為由收尾、縮範圍、或建議開新 session
- Compaction 後繼續工作即可（第一個動作見第 4 條）

**4. Re-grounding 協議**
- 每完成一項 commit + 更新 dashboard 時，同時重讀 goal condition 與 dashboard 未完成清單，輸出一行狀態（例：`3/7 完成，下一項 🤖-4`）再繼續；跨過 checkpoint 段界時，額外核對該段所有項的合約結果都已貼入 dashboard
- 每次 compaction 後的第一個動作 = 重讀 `wave-{id}.md` + ledger 末尾的 RESUME POINTER

**5. 需人裁定事項的非阻塞升級**

遇到必須由使用者裁定的事項（安全決策、scope 變更、破壞性操作）時：

1. **先自行驗證與定性**——親自看過證據，分清「是 bug（自己修）」還是「是決策（交人）」，不把未經驗證的 finding 直接丟給人
2. **盤點依賴**——判斷哪些剩餘工作項不受這個決策影響
3. **不受影響的工作繼續推進**——標記、派發、實作照常，不因待決事項閒置。若該決策封鎖出貨（如安全 HIGH），先宣告封鎖閘門（「此決策未解前本波不標完成」）再繼續其他工作
4. **在下一個自然節點批次呈報**——問題連同進度一起交出，附推薦方案與影響範圍
5. 只有當該決策**阻塞所有剩餘工作**時，才真正停下等待

**6. 環境風格衝突防禦**
- 環境注入的輸出風格（learning / explanatory 等 output style、教學型 hook context）與本 skill 衝突時，**wave 執行期以本 skill 的自主規範為準**
- 具體：不得把工作項的程式碼「留給使用者寫」、不得為教學目的插入額外停點——這違反唯一停點制，且該停點常被自我核對漏報
- 教學價值改放收尾報告（完成後解說設計決策），不犧牲執行連續性

**7. 環境健康守門**
- 偵測到外部依賴不可達（DB、內網 API、LLM endpoint、網路斷線）→ **主動暫停受影響的 in-flight 工作**（含背景 agent，用 SendMessage 通知暫停）——壞環境下繼續跑實驗/測試只會產生垃圾證據
- 暫停原因寫入 ledger「暫停意圖」區（與使用者主動暫停同一機制）；不受影響的工作項照常推進
- 恢復前 controller 親自驗證依賴可達（實跑連線指令取證，不憑推測），驗證過才恢復；恢復用 SendMessage 續跑原 agent，附上環境現況與已驗證證據

**8. 換路煞車**
- 同一方法連續失敗 **2 次** → 停止重試，換方法或回頭重蒐證——不是第 3 次重試。換路前先諮詢 Fable（見「Fable 諮詢協議」諮詢點 2）
- 蹺蹺板偵測：修 A 壞 B、修 B 又壞 A → 退回起點重新定位根因（你在治標不治本）。蹺蹺板也觸發諮詢點 2
- 測試紅 → 先過意圖三方對齊再動手；對齊後測試仍屬錯方 → 修測試並引 requirements 依據
- 發現自己在「猜」而不是「推導」（要寫出「應該可以」「大概是」時）→ 先停下拿證據再動手

### Fable 諮詢協議（askfable）

> **CRITICAL: 四個諮詢點讀 [references/fable-consultation.md](references/fable-consultation.md)（①規劃審查——Phase 4 呈現前必做、②換路煞車、③大項 design review、④batch 分波審查）。`/askfable` 不可用→走缺席降級。**

### 狀態外部化——Dashboard + Ledger 雙層

> **CRITICAL: 記憶不可靠，檔案才可靠。進度狀態一律外部化到兩個檔案，喚醒/恢復/續跑都以檔案 + git 為準。**

| 檔案 | 性質 | 內容 |
|------|------|------|
| `.claude/dev/wave-{id}.md` | 進度快照（就地更新） | 工作項狀態表、合約結果 |
| `.claude/dev/wave-{id}-ledger.md` | append-only 流水帳 | 每次派工/裁決/commit/錯誤一行；末尾維護 RESUME POINTER 與 ERRATA 區 |

**Ledger 格式：** 見 `references/templates.md` 的「Ledger 格式」節，首次建立 ledger 檔時照格式建檔。

**Ledger 使用規則：**
- **每次派工、裁決、commit、錯誤後立即 append 一行**——不等收尾才補；追加用 Edit 工具插在 RESUME POINTER 之前，不用 shell `>>`（會落到檔尾 ERRATA 區之後）
- **ERRATA**：controller 犯錯（誤送訊息、漏跑合約、錯判狀態）→ 記一行「教訓：…」，Subagent-Driven 的心跳 prompt 每次帶上全部條目。**回灌只在本波內、且只在心跳路徑生效**——Inline 執行、compaction 之後、下一波都讀不到它。所以「記了就算處理完」是假的：收尾必須跑 ERRATA 升級判定（收尾流程步驟 4）逐條決定去留，不得留在 ledger 等歸檔（`wave-close.sh` 會連 ledger 一起刪）
- **暫停意圖外部化**：使用者下節流/暫停指令（「usage 快爆了先停」）→ 讓 in-flight 工作跑完、不派新工作，並把暫停意圖寫進 ledger，防止喚醒後誤判為斷線而繼續派工。使用者說「可以繼續」才清除

**中斷恢復協議（git 為準）：**

任何新 session 續跑步驟：
1. cd 進 worktree
2. **先核實 git 真實狀態**：`git log` + `git status` 找已 commit 項與未 commit 半成品——以 git 為準，不以文件記載或記憶為準
3. 讀 `wave-{id}.md` + ledger RESUME POINTER，比對 git 狀態，不一致以 git 修正文件
4. 從第一個真正未完成項續跑

### Subagent-Driven 長跑協議

選 Subagent-Driven 執行方式時讀 [references/subagent-protocol.md](references/subagent-protocol.md) 照做（Brief 第 0 項執行紀律、派工六要素、Brief 分級、模型分層、管線不斷料、心跳 fallback、中斷恢復 SendMessage 優先、Controller 代看門、空跑偵測、Reviewer 不信報告）。

### 驗證合約執行規則

> **CRITICAL: 每個工作項 commit 前，必須按合約跑完所有指令，把實際輸出貼到 wave-{id}.md。**

每個功能完成時：
0. **意圖三方對齊（行為變更前）** — 改動任何既有行為或測試預期之前，先確認現行為／合約與測試預期／規格文件三方一致才動手。不一致＝發現而非障礙：權威順序為 **使用者原話 > 專案既有規格文件（如有） > 驗證合約/測試 > 現行程式行為**，按長跑規範第 5 條呈報，不得默默讓任一方遷就另一方。工作項標題（「修 X」「讓測試過」）不是意圖聲明，不改變權威順序。`INTENT:` 標記需要時才寫。
1. **跑合約指令** — 逐條執行合約裡列的指令
2. **貼實際輸出** — 把終端輸出貼到 wave-{id}.md 的「合約結果」欄（不是寫「passed」，是貼實際輸出）
3. **比對預期** — 輸出 ≠ 預期 → 修到符合，不是改預期
4. **覆蓋場景檢查（自審）** — 合約列的覆蓋場景，逐條比對測試裡的對應 test case 與實際輸出。**缺一場景 = 該項未完成**，不可遺漏、不可「大致有覆蓋」
5. **全過才 commit**

### Wave Dashboard 即時更新

每完成一個功能項的 commit：
1. 更新 `.claude/dev/wave-{id}.md` 對應行的狀態（⏳→✅ 或 ⏳→❌）
2. 填入 commit hash + 合約輸出
3. **多波時：只碰自己的 `wave-{id}.md`，不碰其他 `wave-*.md`**

### 品質閘門（所有工作項完成後）

> **CRITICAL: 所有工作項 commit 完畢、合約全過後，必須跑品質閘門才能標「✅ 完成」。**

#### 安全閘門（合約內已逐項執行）

安全 skill 已寫進各工作項合約（🔒 標記步驟）、逐項 commit 時跑完；此處最終確認 wave-{id}.md 所有 🔒 步驟都有輸出且 0 high/critical，遺漏 → 補跑不可跳過。

#### Typecheck（merge 前唯一同步檢查）

跑專案 typecheck（~90 秒，同步），完整輸出貼 wave-{id}.md。exit 0 才過閘門；FAIL 視同合約失敗，回去修——不得以「與本波無關」自行豁免（真的無關也要修或升級給使用者裁定，因為它出現在本波的門檻上）。

**v0.6 起 merge 前不再跑專案 gate script。** `scripts/hooks/wave-gate.sh` 仍存在，但角色改變：開工基線（`baseline`）與 merge 後的 deep lane 用它——supervisor 每 3 個 merge 跑一次完整 `wave-gate.sh baseline`，紅燈自動開 issue，進 pctl dispatch 迴路修復。gate 內容（測試／ratchet／drift／資料對帳…）由專案 script 自行定義維護，wave 不解析其細節。

#### UX 閘門（批次執行）

依 Phase 4 使用者確認的 UX 審計清單，逐一呼叫：
1. 呼叫對應 skill（`/ui-test`、`/wcag-accessibility-audit`、`/nielsen-heuristics-audit`、`/ux-audit-rethink`）
2. 收集 findings，寫入 wave-{id}.md「🎨 UX 審計結果」區塊
3. 每個 finding 標 severity + 位置 + 建議修法
4. **Advisory 不阻擋**——全部記錄，使用者下波決定是否處理
5. 例外：`/ui-test` 跑出的**功能 bug**（按鈕點不動、表單送不出、頁面 crash）→ 視同合約失敗，必須修
6. **降級規則（worktree 起不了 dev server 時）**：先查 `quality-gates.md`「worktree dev server 啟動方式」照做；仍不可行才允許改「merge 後補跑」——但補跑是**封鎖閘門**：dashboard 狀態只能標「✅ 完成（待 UX 補跑）」，補跑排入合併協助最後一步，補跑完成、結果回寫 wave-{id}.md 後才算真正關波。**禁止**標了「merge 後補跑」就沒有下文

#### 閘門結果影響 wave 狀態

- 安全 0 high/critical + typecheck exit 0 + UX 審計已跑完記錄 → 品質閘門通過，進入收尾流程
- 安全有 high/critical 殘留、或 typecheck FAIL → **不可標「✅ 完成」**，回去修
- UX findings 不影響狀態流轉但必須記錄（不可跳過不跑）；觸發降級規則則只能標「✅ 完成（待 UX 補跑）」，合併協助補跑完成後才升級為「✅ 完成」（見「降級規則」）
- deep lane 紅燈不回溯改本波狀態——另開 issue 走 pctl dispatch 修復

### E2E 驗證責任制

> **CRITICAL: 所有 UI 工作項由 Playwright E2E 驗證交付。**

驗什麼、驗多深自己判斷（歷史教訓供參：漏到客戶端的 blocking bug 都是「無法輸入／crash loop／按了沒反應」這級，開頁 console、輸入欄、主要 CTA 值得優先驗）。測試失敗代表功能有 bug，修到過為止。

E2E spec **檔案的存留政策**（開發期 spec 是否併入 main、驗收 spec 白名單）由專案 gate 管（如 pre-push 白名單擋非驗收 spec）——wave 只管「驗到底」，不規定檔案去留。

### 專案品質鉤子（quality-gates.md）

專案級品質工具透過鉤子檔接入（與 playwright-guide.md 同 pattern）。檔案不存在 = 相關條款全部跳過。

**檔案位置：** `.claude/dev/quality-gates.md`（專案級，由專案自行維護；wave 只讀取不代建——但發現專案有品質工具而無鉤子檔時，向使用者建議建立）

**格式：** 見 `references/hooks-formats.md` 的「quality-gates.md 格式範本」節，建立或檢查鉤子檔時照格式核對。

**Wave 讀取點（兩處，皆屬規劃輔助）：**
1. 開工前必讀 → 知道本專案有哪些 per-item gate
2. Phase 3 合約 → 觸發條件命中的 gate 指令注入對應工作項合約；規模場景引用大案清單

完整品質閘門不由 wave 解析本檔——由 deep lane 跑的 `scripts/hooks/wave-gate.sh` 承擔（該 script 自行消費本檔或內建等效檢查）。

### Playwright 使用指南（自動累積）

E2E 開工前讀指南，解決問題後寫回指南。

**檔案位置：** `.claude/dev/playwright-guide.md`（專案級，每個專案各自維護一份）

**開工前讀：** 寫任何 Playwright 測試前，先讀 `.claude/dev/playwright-guide.md`（不存在就跳過，另見「開工前必讀」）與 `references/e2e-pitfalls.md`（跨專案通用坑，隨 skill 內附），按 pattern 寫、不重新摸索。

**執行中寫：**
每次遇到以下情況，**解決後立即**更新 `.claude/dev/playwright-guide.md`：
- Playwright 測試因非預期原因失敗 → 記下根因 + 解法
- 找到該專案有效的 selector 策略 → 記下 pattern（例：這個專案用 `data-testid` / 用 role / 用 text）
- 找到該專案的 auth/session 處理方式 → 記下 storageState 路徑和設定
- 找到避免 flaky 的有效手段 → 記下（例：等 network idle、waitForSelector 的特定用法）
- 找到該專案 CI vs local 的差異 → 記下

**指南格式：** 見 `references/hooks-formats.md` 的「playwright-guide.md 格式範本」節，建立或更新指南時照格式寫。

**原則：** 每次 append 新段落不刪舊內容（除非過時）、不存在就建且持續維護、不問使用者「要不要記」（靜默維護）。

### 自主決策規則（/goal 執行中遇判斷點）

- UI 細節拿不準 → 做保守版 + 在 wave-{id}.md 標記 `[需確認: 我選了 A 方案因為...]`
- 需要新 dependency → 記到 wave-{id}.md feedback 區，這波不加
- Test flaky → 記到 wave-{id}.md，不花超過 10 分鐘 debug
- Requirements 有 ❓ → 用推薦方案 + 標記 `[自主決策]`（同既有 CLAUDE.md 規則）

### 收尾流程（所有項完成 + 閘門通過後）

> **CRITICAL: 完成宣告不可只看 goal condition。必須同時揭露本波未涵蓋的事項。**

1. **PENDING 盤點**——文件規定但本波未執行的後續動作（deploy/restart/發佈/通知）
   逐一列 `PENDING: <動作> — 待使用者授權`，醒目列入完成報告（與未涵蓋事項揭露並列）——merge
   後需 deploy 的專案，deploy 指令必然出現在此行。
2. 逐條核對 wave-{id}.md「🎯 Goal Condition」區塊並打勾（(1)-(7) 全過才往下），把 `wave-{id}.md` 狀態標「✅ 完成」
   - **打勾必須寫回 dashboard**：核對結果以 `[x] + 一句佐證` 直接編輯進 wave-{id}.md 的 🎯 區塊、隨收尾 commit 進版控——只在對話輸出核對文字 = 沒核對
   - **核對 (7) 不可單勾**：必須在 🎯 區塊 (7) 下方列出本波實際發生的所有停點（時點 + 原因），逐一對照「停點規則」合法清單；單句斷言（「全程僅兩停點」）不算核對。有任何一次停點不在合法清單 → (7) 不可勾，如實記錄違規
   - **不派稽核 subagent 複驗交付物**：合約實跑輸出、typecheck exit code、安全/UX 閘門記錄就是交付物真偽的認定依據（完整品質由 merge 後 deep lane 承擔）。再派一個 agent 重跑一遍屬 over-verification，[官方 Opus 5 指引](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5)明列應移除
   - **消化掉的 backlog 項改為 `done:{wave-id}`**
3. **未涵蓋事項揭露**（每波必做）：
   - **漏項回掃**：回掃 `docs/requirements/` 找有 🔴🟡❓ 但無對應工作項的項目，一律列入清單（含被標「已知延後」「使用者未裁定」的項）——只報事實，延後正當性由使用者判斷。這一步驗的是「有沒有沒做的事」，不是重驗已做的事
   - 讀取本波期間開的 issue（來源 `grill:*` 與執行中冒出的）
   - 在完成報告中**醒目列出**，每筆一行：內容 ＋ 為何本波不能
   - **待裁決事項在收尾報告直接請使用者裁決，不預設開單**——使用者就在收尾停點上，裁決成本最低。裁「修」→ 就地開 followup 工作項執行完才關波；裁「延」→ 才開單。只有使用者未回應而必須關波時，才以「附推薦方案」形式開單
   - 零項時明確寫：「✅ 本波涵蓋所有 grill/spec 決策，執行中無新增未處理事項。」
   - **這段在 goal condition 判定之外**——即使 goal 全綠，未涵蓋事項仍需揭露
4. **ERRATA 升級判定**（ledger 有 ERRATA 條目時必做；須在 merge 與 `wave-close.sh` 之前——ledger 一刪教訓就沒了）：逐條走三問，**全過才算升級候選**，任一不過即按該問的去向處理，不留在 ledger 等歸檔：
   - **Q1 會再犯嗎？**（同型已發生 ≥2 次，或有明確重複條件）→ 否＝一次性手滑，**丟掉不留**
   - **Q2 機器擋得住嗎？** → 是＝寫成 gate script／lint／測試，照 `/issue` 開單（body 註明來源 `errata:{wave-id}`，標題寫「補 gate: …」），**不進 CLAUDE.md**
   - **Q3 讀了會改變行為嗎？**（不是「知道就好」的常識）→ 是＝開 issue 標題冠「升級候選: CLAUDE.md」，實際落點由使用者裁定；否＝丟掉
   - 零條升級時在完成報告明寫「ERRATA N 條，全數判定為一次性，未升級」——沒寫＝沒判定
5. **直接進入合併協助，不徵詢**——讀 [references/multi-wave.md](references/multi-wave.md)「合併協助」節照做（**單波也適用**：merge typecheck、UX 補跑回收、worktree 清理）。唯一仍要停的是步驟 3 的改法矛盾衝突（真需要使用者裁定改法），其餘一路做到 push 完成。**Dispatched 模式：本步與步驟 6 不適用**——push branch 即收尾終點，merge／清理由 supervisor 承擔（見「Dispatched 模式」節）
6. **merge 後清除本波產物**（`bash <kit>/scripts/wave-close.sh {id}`）——波的 dashboard 與
   ledger 在 merge 之後對未來沒有價值，內容留在 git history 即可。腳本會驗證每個檔都已提交
   且無未提交修改（任一不符即中止），把 `git show` 取回指令寫進 `wave-INDEX.md`，再 `git rm`
   dashboard＋ledger＋同 wave_id 的 spec/plan。先跑 `--dry-run` 確認範圍，刪除與 INDEX 一起 commit。
   - **dashboard 裡的「待使用者」事項要先開成 issue**——人眼驗收、seed 重跑、
     待授權的破壞性操作等，清掉 dashboard 等於清掉這些待辦；先落到使用者會看的地方再清。
   - 尚未 merge 就不要清——還沒進 main 的內容，`git show` 只拿得到 branch 上的版本。
   - **為什麼是當場清、而不是標記等歸檔**：舊設計要求收尾寫 frontmatter（`status: done` +
     `closed`），交由 `Stop` hook 的 `archive.sh` 在 N 天後刪除。2026-07-25 實測 dfaa 的 52 個
     `wave-*.md`：**0 個有 frontmatter**，包含當天剛完成、走完整流程且閘門全綠的
     5 個波。條文寫得再明確也沒被執行，於是熱區只增不減。改成呼叫一個指令，消掉兩個失敗點：
     收尾者要記得寫且格式要對、hook 要在 N 天後正確觸發。`archive.sh` 仍在，角色降為漏網補救。

## 多波並行

多波並行規則（隔離策略、`/wave batch`、`/wave status`、`/wave drop`、合併協助）讀 [references/multi-wave.md](references/multi-wave.md)。收尾流程步驟 5 的合併協助亦在該檔。

