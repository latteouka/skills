---
name: kit-audit
description: kit 機制 provenance 稽核——比對 kit 引擎與 dfaa 上游的漂移，逐筆裁定吸收或擱置。觸發詞：/kit-audit、kit 稽核、上游對帳。
disable-model-invocation: true
---

# /kit-audit — kit ↔ 上游 provenance 稽核

## 何時用

手動、低頻（每 4-8 週或 dfaa 大波收尾後）。非 hook 觸發——這是人讀 diff 做裁定的工作，不是閘門。

## 步驟

1. 跑 `bash ~/projects/skills/kit/tools/kit-audit.sh`——輸出三態報告（同步／上游漂移／kit 演化）＋檔案缺失＋無帳機制清單。exit 2 = manifest 本身壞掉（fail-closed），先修 manifest 再稽核。
2. 對每筆「上游漂移」：讀 diff（報告已附 diff 指令），判定：
   - 通用改進 → **吸收**：搬改動進 kit（保持參數化）、更新該行雙 hash + upstream_commit
   - dfaa 特化 → **擱置**：notes 記「擱置@日期：理由」
   - 不確定 → 問使用者，附 diff 摘要與兩案利弊
3. 對每筆「kit 演化」：更新 kit_sha256 + notes（一句話記這次演化是什麼）。
4. 對「無帳機制」：補 manifest 行（kit 自創機制 upstream 記 `kit:original`）。
5. 跑 `bash ~/projects/skills/kit/tests/run.sh` 確認吸收未破壞行為。
6. commit manifest（+ 吸收的檔案改動），並同步 dotfiles 鏡像（有 wave 鏡像慣例的部分）。

## 完成判準（全部可勾稽）

- [ ] `kit-audit.sh` 重跑輸出 0 筆漂移、0 筆缺失、0 筆無帳（exit 0）
- [ ] 每筆擱置在 manifest notes 有理由與日期
- [ ] `tests/run.sh` 全綠
- [ ] manifest 與檔案改動已 commit

## Reference

- manifest 格式與判定矩陣：`tools/kit-audit.sh` 頂註 + `references/declaration-formats.md`「manifest」節
- 上游根覆寫：環境變數 `KIT_AUDIT_UPSTREAM_BASE`（預設 `~/projects`）
