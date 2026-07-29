# Fable 諮詢協議（askfable）

> 透過 `/askfable` skill 派 fable-advisor agent 取得獨立第二意見——繞過壞掉的 server-side advisor tool。以下四個諮詢點在判斷成本最高的節點觸發。`/askfable` 不可用（skill 缺席或主 session 已是 Fable）→ 各點跳過，開工時在 ledger 記一行「本波無 Fable 諮詢」。

**架構差異（vs 舊 advisor）：** fable-advisor 是 fresh agent，看不到主 session transcript——但有 Read/Grep/Bash 工具，可獨立讀檔、跑指令驗證。這是升級不是降級：它給的是**未被主迴圈 framing 污染的獨立意見**。所有脈絡必須組裝進 prompt 或落檔讓 agent 自行 Read。

## 四個諮詢點

皆為「人工 review 前」或「判斷已被污染時」，不是「完工後複查」：

1. **規劃完成、Phase 4 呈現前**——先把計畫草稿落到 scratch 檔，派 fable-advisor 獨立審查。Prompt 指示 Fable：
   - 自己跑一輪 Phase 2 四來源掃描指令，列出「我掃到但你清單上沒有」的項（獨立驗證 loop-until-dry）
   - 抽查合約：預期輸出是否具體、覆蓋場景缺不缺 edge/誤用/守恆
   - 規模與依賴排序是否合理
   - **防違規建議 guard**：Fable 意見中違反 Core Principles 的建議（縮範圍、加停點、禁語句型）→ 記 ledger「Fable 建議 X，違反〈禁止端出縮減版〉，不採納」，規模疑慮的合法出口是 Checkpoint 分段
   - 發現缺口先修再呈給使用者（省一輪人工來回）

2. **換路煞車觸發時**（第 8 條，含蹺蹺板偵測）——Prompt 紀律遵循 askfable 防 anchoring 規則：附「試過什麼＋實際錯誤輸出＋相關檔案路徑」（事實），**不附「我猜根因是 X」**（污染源）。Fresh context 在此反而是升級——不繼承主迴圈的錯誤假設。Fable 指的路優先嘗試。Subagent-Driven 時：implementer 觸發煞車停手回報，**由 controller 諮詢**再 SendMessage 帶結論續跑原 agent。意見衝突時用 SendMessage 追問同一 agent（保脈絡），不重派

3. **大項 design review**（Subagent-Driven 執行期，`task-N-design.md` 落檔後、呈使用者 review 前）——僅 Brief 分級為「大項」（schema 變更、跨系統、多檔）時觸發，一波 0-2 次。Fable 直接 Read `.superpowers/sdd/task-N-design.md`，脈絡組裝成本近零。問：設計與現有 schema/架構的相容性、遷移風險、被否決的替代案是否真該否決、該項合約能否驗到設計宣稱的行為

4. **`/wave batch` 分波結果審查**（分組＋預測交集表呈使用者過目前）——一次 batch 一次呼叫。問：檔案範圍分組有無漏算的相交、依賴順序有無成環或顛倒、「可並行組合」是否高估

**不設收尾終檢諮詢點**：完工後再請一個模型複查交付物屬 over-verification，[官方 Opus 5 指引](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5)明列應移除。交付物真偽由合約實跑輸出與 gate script exit code 認定，不由第二個模型的意見認定。**逐項 commit 前也不諮詢**——N 項 × 30-90 秒，且與 reviewer 親自重跑合約完全重複。

## 諮詢紀律

- **呼叫前先 durable**：計畫草稿或 design doc 落檔後才呼叫——askfable 耗時 30-90 秒，session 若中斷，落檔的成果還在；諮詢點 1 因 Phase 4 前尚無 commit，改落 scratch 檔
- **不默默改道**：Fable 意見與既有證據衝突時，用 SendMessage 對同一 agent 追問（「我查到 X，你建議 Y，哪個約束決勝？」），不悄悄換方向也不悄悄無視
- **每次諮詢記 ledger 一行**：`[HH:MM] askfable 諮詢點 N：{採納/反駁+理由一句}`
- askfable 是 Agent tool 呼叫、不是停點——執行期間照常，不違反唯一停點制
- **缺席降級**：比照「相依 Skill 缺席降級」pattern——ledger 一行、不卡流程
