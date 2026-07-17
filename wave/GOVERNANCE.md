# Wave Skill 治理（維護者文件，不載入執行期）
**Created**: 2026-07-17

## 新條款三律
1. Fixture 先行：先有「現版失敗、新版通過」的 testbed 證據才轉正；null 即不加
   例外通道：無法本地 fixture 驗證的條款，得以（a）外部實證（如 fable eval 具體輪次數據）或
   （b）floor-guard 定位（本地 null 但目標 tier 有實證/實戰失敗案例）上線——兩者皆須 provenance 帳本標注依據並列入閱卷觀察名單。
2. 綁動作 artifact：條款綁編號動作、產出具名可重跑 artifact；缺席型義務走終端 artifact gate
3. 加一減一：每次整合附刪減清單；core 硬上限 800 行（scripts/wave-lint.sh 強制）

## 例行
- 每輪閱卷報告必附「刪減候選」：連續兩輪未防住任何失分且未被引用的條款
- 條款出處帳本：dotfiles docs/wave-testbed/clause-provenance.md
- 價值宣言凍結清單（只減不增）：
  1. **「做好比做快重要；Session 跑再久都沒關係，品質是唯一標準。」**
     機制版：品質優先段 CRITICAL（寧可 3 項零 bug 不要 6 項回頭修）＋ 長跑規範 3（禁止以 context 為由收尾）。
  2. **「長工作不受單一 session 存活限制。」**
     機制版：長跑規範 3 ＋ 狀態外部化/中斷恢復協議（git 為準跨 session 續跑）。
- 鏡像流程：skills repo commit → rsync → dotfiles mirror commit；`make wave-mirror-check` 驗證
