# Wave Skill 治理（維護者文件，不載入執行期）
**Created**: 2026-07-17

## 新條款三律
1. Fixture 先行：先有「現版失敗、新版通過」的 testbed 證據才轉正；null 即不加
   例外通道：無法本地 fixture 驗證的條款，得以（a）外部實證（如 fable eval 具體輪次數據）或
   （b）floor-guard 定位（本地 null 但目標 tier 有實證/實戰失敗案例）上線——兩者皆須 provenance 帳本標注依據並列入閱卷觀察名單。
2. 綁動作 artifact：條款綁編號動作、產出具名可重跑 artifact；缺席型義務走終端 artifact gate
3. 加一減一：每次整合附刪減清單；core 硬上限 800 行（scripts/wave-lint.sh 強制）
4. 禁止「完工後複查」型條款：新條款若要求在工作完成後再派 agent／再請一個模型複驗自己的產出，一律不收——[官方 Opus 5 指引](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5)明列此類為 over-verification。品質不足要補的是 deterministic gate（gate script／lint／測試 exit code），不是多一層模型意見。（2026-07-25 據此移除抗辯／收尾稽核／advisor 諮詢點 3-4，見 provenance 帳本「已移除條款」）

## 例行
- 每輪閱卷報告必附「刪減候選」：連續兩輪未防住任何失分且未被引用的條款
- 條款出處帳本：dotfiles docs/wave-testbed/clause-provenance.md
- 價值宣言凍結清單（只減不增）：
  1. **「做好比做快重要；Session 跑再久都沒關係，品質是唯一標準。」**
     機制版：品質優先段 CRITICAL（寧可 3 項零 bug 不要 6 項回頭修）＋ 長跑規範 3（禁止以 context 為由收尾）。
  2. **「長工作不受單一 session 存活限制。」**
     機制版：長跑規範 3 ＋ 狀態外部化/中斷恢復協議（git 為準跨 session 續跑）。
- 鏡像流程：skills repo commit → rsync → dotfiles mirror commit；`make wave-mirror-check` 驗證

## 邊界宣告：wave 不認識呼叫端

Wave 的合約止於 `git push -u origin <branch>`。任何條款不得提及特定呼叫端（中控／supervisor／CI／某專案的 deep lane），也不得依賴「之後誰會 merge」。理由：wave 是純開發引擎，一旦條文寫進某個編排器的分工，該編排器改版就得改 skill，而 skill 是 LLM 每次載入的行為規格——耦合成本按次數計。

唯一保留的環境旗標是 `WAVE_UNATTENDED=1`，語意限定為「現場沒有人可問」，不承載任何呼叫端身分。

### 刪減清單（加一減一律）

本輪純減，無新增條款：
- `Dispatched 模式` 節（6 條）→ 收窄為 `無人值守模式`（4 條），merge 相關覆寫全刪
- 停點規則「合併協助例外」整條刪除
- 收尾流程步驟 5「合併協助」＋步驟 6「wave-close.sh／wave-INDEX.md」→ 併為「清產物 → push 收工」兩步
- `references/dispatched-mode.md` → `references/unattended-mode.md`（supervisor 分工表、外部合約引用、事故編號全刪）
- `references/multi-wave.md`「合併協助」→「合併參考（wave 流程外）」，降為非流程材料
