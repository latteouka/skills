---
name: kit
description: 專案工程機制安裝器與回饋管理引擎。用於：在新專案安裝工程機制模組（/kit-init，含 onboarding 訪談）、整理收件匣（/triage）。觸發詞：/kit-init、/triage、安裝 intake、整理收件匣、triage。
argument-hint: "--intake|--backlog|--rtm|--wave-gates|--ratchet|--ctl|--all（模組安裝）｜無參數＝onboarding 訪談｜/triage＝整理收件匣"
---

# Kit — 工程機制安裝器

> 本檔是 `/kit-init` 與 `/triage` 的入口。kit **package** 另內含八個子 skill
> （各自獨立 symlink 進 `~/.claude/skills/`、各有自己的 SKILL.md）：
> `wave`、`grill-me`／`grill-with-docs`／`brainstorm`、`debug`、`plans`、
> `sdd`、`kit-audit`。vendored 上游包住 repo 頂層由 `vendors.conf` 同步。

## 三個用途

### 1. `/kit-init --<module>` — 模組化安裝

執行 `installers/kit-init.sh`（dispatcher）：參數解析 → 依賴檢查（缺失報錯
提示，**不自動帶裝**）→ 依賴序執行（intake → backlog → wave-gates → rtm →
ratchet）→ 彙總。全部冪等：已存在的檔案／marker／hook 條目一律 skip，重跑
diff 零。未知參數 exit 2。

| 模組 | 安裝內容 | 依賴 |
|---|---|---|
| `--intake` | inbox＋backlog scaffold、intake.config.yaml、5 個 hook | — |
| `--backlog` | 一筆一檔 backlog 目錄、backlog-lint 掛 pre-commit | intake |
| `--rtm` | matrix scaffold、rtm-check gate、reqsync 雙 hook、讀側雙 hook、CLAUDE.md 協議段、config 回填、gitignore | intake |
| `--wave-gates` | kit.yaml wave 段、gates.d／canary.d／pathspec-targets scaffold、merge-train 掛 .husky | backlog |
| `--ratchet` | kit.yaml ratchet 段、counters.d scaffold、ratchet gate stub、baseline 初始化指引 | wave-gates |
| `--ctl` | kit.yaml `ctl_*` 能力宣告三鍵（預設全保守）＋後續人工步驟指引（registry 註冊**刻意不自動**——防自我授權；合約見 dotfiles/docs/portfolio-ctl/） | — |
| `--hygiene` | **K7 交付，未實裝**——單獨呼叫 exit 1；--all 列 skipped | — |
| `--ui` | 同上（K7） | — |
| `--ops` | 同上（K7） | — |

`--all`＝已實裝六模組依序全裝（含 ctl）、未實裝列 skipped(K7 交付)、整體 exit 0。
`--non-interactive` 透傳 intake（測試／自動化）。

### 2. `/kit-init`（無參數）— onboarding 訪談

installer 只管寫入；「裝什麼、怎麼配」的判斷樹在此，由 LLM 執行：

1. **偵測**：專案型態（node？monorepo？有無 .husky）、已裝模組
   （intake.config.yaml／backlog/INDEX.md／gates.d 存在性）、有無正式需求文件。
2. **三檔組合推薦**（使用者選檔後照表跑 dispatcher 對應參數）：
   - **最小組**＝intake＋backlog＋rtm（回饋管線＋規格真理層——RTM 是核心，最小組也含）
   - **標準組**＝最小組＋wave-gates＋ratchet（收尾閘門＋品質債 ratchet）
   - **全套**＝標準組＋hygiene／ui／ops——**K7 未實裝，明示降級**：先裝標準組，K7 落地後補
3. **RTM 建檔子流程**：照 `references/rtm-authoring.md`（有正式文件→抽取＋
   判斷題校正；無文件→as-built 反向盤點）。installer 只放 1 條 planned 的
   scaffold matrix（天然過 rtm-check），真條目由訪談產出後刪 scaffold。
4. **產出＋降級明示**：列已裝／略過清單、kit.yaml 待填欄位（reqsync_anchors、
   merge_prep_cmd、tool_readiness…）、ratchet baseline 首跑指令、gates.d 範例
   stub 待替換。**留空欄位＝功能降級，必須說出口**，不靜默。

**progress 檔**：`.kit-init-progress.yaml`（專案根）——訪談跨多輪、可能中斷，
只記路徑選擇＋已校正章節；**由 SKILL（LLM）讀寫，installer 無感**。恢復判準：
matrix 有草稿但 rtm-check 未過＝建檔中斷，讀 progress 檔續跑；已過＝殘留直接刪。
細節見 `references/rtm-authoring.md`「中斷恢復」節。

### 3. `/triage` — 整理收件匣

讀 `references/triage-rules.md` 全文，對 `.claude/dev/inbox.md` 每一筆執行
判斷樹，結果寫入 `.claude/dev/backlog/`。

**此指令通常不需手動下**——`/wave --from backlog` 開波時若偵測到未整理項會
自動先跑。手動觸發用於想提早看清單時。

## 設計原則

**觸發權歸 hook，知識歸 skill。** 本 skill 不負責「什麼時候做」——捕捉由
`UserPromptSubmit` hook 無條件執行，積壓提醒由 `SessionStart`，歸檔由 `Stop`，
RTM 提醒由 `PostToolUse`。skill 只承載需要語意推理的判斷樹（triage、onboarding
訪談）。凡是設計裡出現「Claude 應該主動記得 X」，就該問：這能不能改成 hook？

## 檔案

| 路徑 | 用途 |
|---|---|
| `installers/kit-init.sh` | 模組化 dispatcher（依賴檢查＋依賴序執行） |
| `installers/intake.sh`／`installers/modules/` | intake 安裝器／backlog·rtm·wave-gates·ratchet 模組 |
| `templates/kit.yaml` | 主宣告檔模板（欄位規格見 references/declaration-formats.md） |
| `lib/common.sh` | 共用函式（config／marker 區塊／mkdir 鎖／編號） |
| `hooks/` | capture／summary／archive／wave-awareness／rtm-touch-reminder／rtm-session-start 等 |
| `engines/` | wave-gate／ratchet／rtm-check／canary／pathspec-liveness |
| `references/triage-rules.md` | triage 判斷樹（本 skill 的核心知識） |
| `references/rtm-authoring.md` | RTM 建檔訪談指南（onboarding 子流程） |
| `tests/run.sh` | 測試（`bash tests/run.sh`） |
