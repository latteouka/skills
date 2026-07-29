---
name: kit
description: 專案工程機制安裝器與回饋管理引擎。用於：在新專案安裝 intake 機制（/kit-init --intake）、整理收件匣（/triage）。觸發詞：/kit-init、/triage、安裝 intake、整理收件匣、triage。
argument-hint: "--intake（安裝）｜不帶參數＝整理收件匣"
---

# Kit — 工程機制安裝器

> 本檔只是 `/kit-init` 與 `/triage` 兩個指令的入口。kit **package** 另內含八個
> 子 skill（各自獨立 symlink 進 `~/.claude/skills/`、各有自己的 SKILL.md）：
> `wave`（波次引擎）、`grill-me`／`grill-with-docs`／`brainstorm`（訪談）、
> `debug`、`plans`、`sdd`、`kit-audit`（provenance 稽核）。判準：自創且屬開發
> 管線成員才進本 package；vendored 上游包（安全／UX 審計）住 repo 頂層由
> `vendors.conf` 同步。

## 兩個用途

### 1. `/kit-init --intake` — 在本專案安裝 intake 機制

執行 `installers/intake.sh`，它會：建立 `.claude/dev/{inbox,backlog}.md`、互動產生
`intake.config.yaml`、把三個 hook merge 進專案 `.claude/settings.json`。

**冪等**：已存在的檔案與 hook 條目跳過不覆寫。

### 2. `/triage` — 整理收件匣

讀 `references/triage-rules.md` 全文，對 `.claude/dev/inbox.md` 每一筆執行判斷樹，
結果寫入 `.claude/dev/backlog.md`。

**此指令通常不需手動下**——`/wave --from backlog` 開波時若偵測到未整理項會自動先跑。
手動觸發用於想提早看清單時。

## 設計原則

**觸發權歸 hook，知識歸 skill。** 本 skill 不負責「什麼時候做」——捕捉由
`UserPromptSubmit` hook 無條件執行，積壓提醒由 `SessionStart`，歸檔由 `Stop`。
skill 只承載需要語意推理的判斷樹。

理由：LLM 對「現在該不該叫這個 skill」的判斷是 drift 源。凡是設計裡出現
「Claude 應該主動記得 X」，就該問：這能不能改成 hook？

## 檔案

| 路徑 | 用途 |
|---|---|
| `lib/common.sh` | 共用函式（config／frontmatter／mkdir 鎖／編號） |
| `hooks/capture.sh` | UserPromptSubmit：捕捉 |
| `hooks/summary.sh` | SessionStart：積壓摘要 |
| `hooks/archive.sh` | Stop：清除逾期已完成的波（刪除＋INDEX 留取回指令） |
| `references/triage-rules.md` | triage 判斷樹（本 skill 的核心知識） |
| `references/patterns.txt` | 弱信號詞庫 |
| `installers/intake.sh` | 安裝器 |
| `tests/run.sh` | 測試（`bash tests/run.sh`） |
