# Wave 深度材料 — E2E 跨專案通用坑

本檔由 wave/SKILL.md「Playwright 使用指南」節於寫 E2E 前載入。
（vendored 自維護者 `~/projects/E2E-PITFALLS.md` @2026-07-24，setraining 2026-04-10 CI flaky debug 實戰蒸餾；上游更新時同步）

## Contents
1. Auth rate limiting vs 單一 CI runner IP（最常見）
2. 登出測試不可用 shared storageState
3. waitForFunction 輪詢不如 waitForURL
4. Confirm dialog 同名按鈕 strict mode violation
5. next-env.d.ts 被 dev server 自動改寫
6. disableSignUp 阻斷 seed.ts HTTP 寫法
7. E2E pitfall debug 心法

## 1. Auth rate limiting vs 單一 CI runner IP ⚠️ 最常見

**症狀：** E2E 本地穩定過，CI 上「第 N 個登入測試」偶發 flaky，first attempt timeout、retry 卻過。

**根因：** better-auth / NextAuth 等框架常內建 rate limit（如 `{ window: 60, max: 5 }`）。CI 所有 request 來自同一個 runner IP，一輪 suite 發起 4-10 個 auth request，容易在 window 內撞上限。429 被擋後瀏覽器看起來像 login 沒反應，`waitForURL` / `waitForFunction` timeout。Playwright retry 時 window 重置，測試就過了。

**Debug 訊號：** retry 總是過 → 外部 stateful 因素；調高 timeout 無效 → 429 是即刻的不是慢；只有「後面」的登入測試 flaky → 前面累積了 counter。

**修法：** 用 `E2E_TEST=true` env flag 旁路 rate limit（與 IP 白名單旁路同 pattern）：

```ts
rateLimit: {
  enabled: process.env.E2E_TEST !== "true",
  window: 60,
  max: 5,
},
```

不要「寫死高上限」，production 行為要保持不變。

## 2. 登出測試不可用 shared storageState（session 污染）

**症狀：** 登出測試改用 global-setup 的 shared storageState，後續 50+ 個測試連鎖爆炸。

**根因：** `storageState` 是 **client-side 快照**（cookies + localStorage），但 better-auth / NextAuth 的 session 驗證是 **cookie token 比對 DB session record**。測試 A 登出 → 後端刪 DB session → 測試 B 載入相同 cookie → server 認不出 → 全部失效。

**修法：** 登出測試**必須**用 `browser.newContext({ storageState: { cookies: [], origins: [] } })` 建 fresh context，自己重新登入、登出，不污染共用 session。即使登入會踩到坑 #1 的 rate limit 也要這樣做。

## 3. `waitForFunction(() => location.pathname === ...)` 不如 `waitForURL`

**症狀：** 登入後等 redirect 偶發不穩。

**根因：** `waitForFunction` 是 50ms 輪詢 `window.location`；React 19 transition / concurrent rendering 可能讓 URL 更新與渲染不同步，輪詢錯過狀態。

**修法：** 用 `page.waitForURL("/", { timeout: 30_000 })` 或 `page.waitForURL(/\/$/)` —— 走 navigation event，比輪詢穩。

## 4. Confirm dialog 按鈕同名造成 strict mode violation

**症狀：** 加了「操作前確認」AlertDialog（登出、刪除）後 E2E 壞掉。

**根因：** dialog 打開後，觸發按鈕與 dialog 內確認按鈕同名，strict mode 抓到兩個 locator 就爆。

**修法：** 第二次點擊 scope 到 dialog：

```ts
await page.getByRole("button", { name: "登出" }).click(); // 開 dialog
await page
  .getByRole("alertdialog")
  .getByRole("button", { name: "登出" })
  .click(); // 在 dialog 內確認
```

用 `alertdialog` role 當 scope 比 `.last()` / `.nth(1)` 更有語義、更穩。任何新增確認 dialog 的 commit 必須同步更新對應 E2E。

## 5. `next-env.d.ts` 被 dev server 自動改寫

**症狀：** 跑過 `pnpm dev` 後 `git status` 出現莫名的 `next-env.d.ts` diff。

**根因：** Next.js 16 dev server 會自動 mutate 這個檔案。

**修法：** commit 前 `git checkout -- next-env.d.ts` 還原，不 commit 這個 diff。

## 6. `disableSignUp: true` 阻斷 `seed.ts` 的 HTTP 寫法

**症狀：** `pnpm tsx prisma/seed.ts` 回 `MISSING_OR_NULL_ORIGIN` 或 `EMAIL_AND_PASSWORD_SIGN_UP_IS_NOT_ENABLED`。

**根因：** seed.ts 透過 `fetch` 呼叫 `/api/auth/sign-up/email` 建帳號，better-auth 開 `disableSignUp: true` 後這條路斷了；Prisma 備案只建 User 不建 Account record（沒密碼 hash），登入仍失敗。

**修法：** 用 `prisma/seed-ci.ts` pattern —— `import { hashPassword } from "better-auth/crypto"`，手動 `db.user.create` + `db.account.create`。CI 與本地首次 setup 都走這條。

## 7. E2E pitfall debug 心法

- **Retry 過 = 不是測試邏輯錯，是外部 stateful 因素**。先問「環境有什麼 stateful 且會在 retry 間變化」，不要先改測試。
- **調 timeout 無效 = 不是慢，是被擋**。Timeout 只治 slow，不治 fail fast。
- **看第一次失敗的真正錯誤訊息**，不是 retry 後的通過假象（`gh run view <id> --log` 找 first attempt stack trace）。
- **比對失敗與成功測試的差異**：同 pattern 一穩一 flaky，差異必是順序/累積狀態（坑 #1 典型）。
- **CI 的 playwright-report 要 upload artifact**（`if: failure()`），留 screenshot + trace，否則只能瞎猜。
