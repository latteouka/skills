# Wave 深度材料 — 驗證合約範例

本檔由 wave/SKILL.md 於對應動作點載入——不要直接執行本檔。

## 五個驗證合約範例

```markdown
### 🤖-1: 訂單篩選 API
**驗證合約：**
1. `pnpm vitest run src/server/api/routers/order.test.ts` → ≥5 tests passed
2. Happy path：空篩選回全部 / 多條件交集 / 無結果回空陣列
3. Edge case：日期範圍頭尾相同 / 金額為 0
4. 誤用：不存在的篩選欄位 → 400 / SQL injection 字串 → 安全處理

### 🤖-2: 訂單篩選 UI
**驗證合約：**
1. `pnpm vitest run src/server/api/routers/order.test.ts` → passed（API 層）
2. `pnpm playwright test tests/order-filter.spec.ts` → passed
3. Happy path：選篩選條件→表格更新 / 清除篩選→回全部 / 無結果顯示空狀態
4. 誤用：快速連點篩選按鈕 → 不重複發 request / 篩選中切頁再回來 → 狀態保持

### 🤖-3: API token 驗證機制
**驗證合約：**
1. `pnpm vitest run src/server/auth.test.ts` → ≥3 tests passed
2. Happy path：valid token → 200 / expired token → 401
3. Edge case：malformed token / empty string / null
4. 誤用：token 洩露到 response body / log
5. 🔒 `/insecure-defaults` 掃描 auth 相關檔案 → 0 high/critical
6. 🔒 `/sharp-edges` 掃描 API 設計 → 0 high/critical

### 🤖-4: 訂單詳情頁
**驗證合約：**
1. `pnpm playwright test tests/order-detail.spec.ts` → passed
2. Happy path：導航到詳情→資料正確 / 編輯→儲存成功
3. 誤用：未儲存就離開→提示 / 必填欄位清空→擋提交 / 權限不足→導轉或禁用
4. 截圖自檢：頁面佈局不破版、元素正確渲染

### 🤖-5: 匯入檔解析器（資料管線類範例）
**驗證合約：**
1. `pnpm vitest run src/scripts/parse/foo-parser.test.ts` → passed
2. Happy path：樣本檔解析 → 各 model 計數 = 預期值
3. Edge case：欄位缺失 / 空檔 / 超大檔
4. 誤用：格式毀損檔 → 整檔標 FAILED，不部分寫入
5. 資料守恆：來源筆數 vs 落庫筆數對帳（差異 0 或逐項解釋）/ 同檔重跑兩次各表計數不變 / skip 計數輸出且低於閾值
```
