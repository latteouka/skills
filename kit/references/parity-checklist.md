# parity-checklist — K6 Step B 操作手冊（隔離 parity harness）

**Created**: 2026-07-30

K6 Step B 目標：逐腳本證明「dfaa 舊腳本 vs kit 引擎」行為全等，等價確認後舊腳本才退役為 3 行 shim。本手冊列工具用法、dfaa 狀態型腳本的建議參數對照，以及**腳本驗不到的 UNVERIFIABLE 手動項**。

## 1. parity-run 用法

```
bash kit/tools/parity-run.sh --source <dfaa-主repo路徑> --ref <同一 commit> \
  --cmd-a "<舊腳本指令>" --cmd-b "<kit shim/引擎指令>" \
  [--workdir-rel <相對路徑>] [--env KEY=VAL ...] [--state-glob <glob> ...]
```

- 隔離雙 clone（`git clone --no-hardlinks`，連 `.git` 狀態都隔離）——舊版先跑不會替新版修好環境（消耗 preauth、寫 stamp、tighten baseline 全被 clone 邊界擋住）。
- `--source` 給**主 repo 路徑**，不要給 linked worktree 路徑（clone 對 worktree 的行為未驗證）。
- `--ref` 兩邊同一 commit——比的是行為差異，不是版本差異。
- 五面向對帳：exit-code／output(normalized)／working-tree／state-glob／untracked-set。判讀尾行：`PARITY:EQUIV`（exit 0）＝全等；`PARITY:DIFF`（exit 1）＝逐面向看 DIFF 摘錄（`<`＝A、`>`＝B）；exit 2＝fail-closed（參數、clone、cmd 起不來），先修環境再談等價。
- `--state-glob` 未指定時預設 `.claude/dev/.wave-*` 與 `.git/wave-*`。

## 2. dfaa 狀態型腳本對照表（草稿——K6 逐列補實跑參數）

cmd-a＝dfaa 舊腳本、cmd-b＝kit 對應。狀態型腳本每個子指令分開比，不要串在同一次 parity-run 裡（串行又把污染帶回來了）。

| dfaa 舊腳本 | kit 對應 | 狀態面 | 建議 --state-glob／注意 |
|---|---|---|---|
| `scripts/hooks/wave-closure-lock.sh` | `kit/gates/merge-train/wave-closure-lock.sh` | closure lock：git-common-dir 下 `wave-closure.lock/` | `--state-glob ".git/wave-closure.lock*"`；acquire／release／status 各驗一輪 |
| `scripts/hooks/wave-regate-guard.sh` | `kit/gates/merge-train/wave-regate-guard.sh` | regate stamp＋preauth：`.git/wave-regate-pass`、`.git/wave-regate-preauth` | `--state-glob ".git/wave-regate-*"`；stamp／preauth／check 各子指令分開比——check 會**消耗** preauth，正是串行污染母題 |
| `scripts/hooks/wave-merge-prep.sh` | `kit/gates/merge-train/wave-merge-prep.sh` | 改依賴：merge 動 working tree＋index＋refs | working-tree 面向為主；`--workdir-rel` 對齊 repo 根 |
| `scripts/hooks/ratchet.sh` | `kit/engines/ratchet.sh` | baseline：`quality-baseline.json`（tracked） | tighten 模式改 tracked 檔——working-tree 面向直接抓；比對模式與 tighten 模式分開跑 |
| `scripts/hooks/wave-gate.sh` | `kit/engines/wave-gate.sh` | 組合狀態（編排呼叫上列腳本） | 先比葉子腳本、全綠後再比總編排，否則 DIFF 無法歸因 |
| `scripts/hooks/__tests__/canary.sh` | `kit/engines/canary.sh` | 低狀態（scratch 自隔離） | 預設 glob 即可 |

## 3. shim-probe（退役殼保真）

```
bash kit/tools/shim-probe.sh
```

驗標準 3 行 shim（`exec bash <target> "$@"`）四項 round-trip：argv 逐位（含空白與引號參數）、cwd、env、exit code。`.ts` 版（`exec tsx`）同構；tsx 不在 PATH 時 SKIP 明示——**SKIP 不是 PASS**，K6 退役 `.ts` 腳本前必須在有 tsx 的環境補跑一次。

Husky 面向（真 git hook 鏈）已由常駐 selftest 覆蓋：`kit/tests/cases/parity-harness.sh` 用 `git config core.hooksPath .husky` ＋真 `git commit` 證明 hook 鏈與直呼等價（機制與 npm husky 一致，不裝 node 依賴）。

## 4. UNVERIFIABLE 手動清單（腳本驗不到，逐條人工簽收）

> parity-run／shim-probe 全綠 ≠ 下列項目已驗。K6 Step B 收尾時逐條打勾，勾不了的標注理由入 dashboard。

- [ ] **Claude settings.json 接線**：hooks 接線改動需 session restart 才生效，腳本無法驗證「重啟後的 session 真的走新接線」。手動：改完接線 → 重啟 session → 觸發一次對應 hook → 看 hook 輸出確認走的是 kit 路徑。
- [ ] **macOS 檔案系統大小寫差異**：A/B 兩 clone 落在同一個 case-insensitive volume，大小寫碰撞類 bug 兩邊同盲、parity 看不出。手動：關鍵腳本在 case-sensitive volume（`hdiutil` 建 case-sensitive 映像）或 Linux CI 上重跑一次比對。
- [ ] **真 push 觸發的 pre-push**：parity-run 不做真 push（需要遠端且不可逆）；selftest 的 Husky 面向只覆蓋 pre-commit。手動：throwaway remote（`git init --bare` 本地裸 repo 當 origin）對 dfaa 舊 pre-push 與 kit 版各 push 一次，比攔截行為與輸出。
