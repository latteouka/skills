// kit/engines/rtm-check.ts — RTM 一致性檢查引擎（吸收自 dfaa scripts/rtm-check.ts，K5 參數化）
//
// RTM 存活條件＝至少一個機器消費者（機器不消費的文件必然腐爛）。
// 本 script 就是第一個消費者：wave-gate／pre-push 呼叫，exit code 是唯一介面。
//
// 檔案結構：<matrix_dir>/*.yaml，每檔：
//   meta: { section, total_clauses }   ← per-file 條文守恆錨
//   entries: [ { req_id, req_text, status, detail_specs, impl_routes,
//                impl_details, notes, last_discussed, verify } ]
// 向下相容：req_id/req_text 缺席時讀 rfp_id/rfp_text（dfaa 存量 matrix 不用改）；
// impl_routes/verify 等額外欄 passthrough 不驗不擋。
//
// 檢查（fail-closed，任一違規 exit 1）：
//   1. 每檔 yaml 可解析、meta.total_clauses == entries 數
//   2. req_id 跨檔全域唯一；entry 的 req_id 前綴須與該檔 meta.section 一致
//   3. status ∈ status_enum（宣告，預設 implemented/partial/divergent/planned/na）
//   4. rtm_notes_required 狀態（預設 divergent）→ notes 必填非空
//   5. rtm_detail_specs_required 狀態（預設 implemented/partial/divergent）→ detail_specs 非空
//   6. rtm_impl_details_required 狀態（預設 implemented/partial）→ impl_details 非空
//   7. impl_details 內抽出的檔案路徑必須真實存在（suffix match against git ls-files，
//      再 fallback 到 impl_path_bases 宣告基準的直接路徑檢查——上游硬編碼
//      ["", "apps/web", "apps/web/src", "apps/web/prisma/schema"] 的參數化）
//
// [kit 參數化seam]
//   CLI：--repo-root <path>（預設 git rev-parse --show-toplevel）、--emit-index
//   宣告：<repo-root>/.claude/kit/kit.yaml（flat-key，與 lib/common.sh kit_decl_get
//   同語意的 grep 式解析——不用 js-yaml 解 kit.yaml，維持與 bash 側消費者一致）：
//     matrix_dir（預設 docs/rtm/matrix）
//     status_enum（空白分隔；PASS 統計行欄序＝宣告序）
//     impl_path_bases（空白分隔；"." 表 repo 根）
//     rtm_nonpath_tokens（空白分隔；上游 KNOWN_NON_PATH_TOKENS 的宣告化，
//       預設 "Next.js Node.js"）
//     rtm_notes_required / rtm_detail_specs_required / rtm_impl_details_required
//
// --emit-index（讀側）：檢查全綠後複用 check7 抽取結果產
//   <repo-root>/.claude/kit/rtm-index.tsv（檔案→條目反查表；gitignored 衍生物）。
//   格式：首行 `# rtm-index v1 matrix_hash=sha256:<hex>`（hash＝matrix/*.yaml
//   以檔名排序串接後 sha256，bash 側 `LC_ALL=C find/sort + cat | shasum -a 256`
//   可重現——兩側同值由 tests/cases/rtm-check.sh 看守）；資料列
//   `<repo-root 相對路徑>\t<req_id>\t<matrix 檔名>`（suffix 一對多時全 emit）。
//
// 執行時 runtime：node ≥23.6（type stripping 直跑）或 tsx；js-yaml 用
// createRequire 從「目標專案」node_modules 解析（kit 零 node 依賴不變——
// rtm 模組要求專案自備 js-yaml）。
//
// 用法：node kit/engines/rtm-check.ts --repo-root <path> [--decl-dir <path>] [--emit-index]
// 統計輸出：整體＋各檔 status 計數——pass 時仍輸出（最小覆蓋率報表；
// 訊息與統計行格式逐位保留上游，dfaa parity 由 K5 🤖-C 合約看守）。

import * as fs from "node:fs";
import * as path from "node:path";
import * as crypto from "node:crypto";
import { execFileSync } from "node:child_process";
import { createRequire } from "node:module";
import { pathToFileURL } from "node:url";

// --- CLI 參數 -------------------------------------------------------------

let ROOT = "";
let emitIndex = false;
let declDirOverride = "";
{
  const argv = process.argv.slice(2);
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--repo-root") {
      ROOT = argv[++i] ?? "";
    } else if (a === "--decl-dir") {
      // 測試 seam（K2 引擎慣例）：宣告目錄覆寫，預設 <repo-root>/.claude/kit
      declDirOverride = argv[++i] ?? "";
    } else if (a === "--emit-index") {
      emitIndex = true;
    } else {
      console.error(`rtm-check: 未知參數 ${a}`);
      process.exit(2);
    }
  }
}
if (!ROOT) {
  try {
    ROOT = execFileSync("git", ["rev-parse", "--show-toplevel"], { encoding: "utf8" }).trim();
  } catch {
    ROOT = "";
  }
}
if (!ROOT) {
  console.error("rtm-check: 不在 git repo 內且未給 --repo-root");
  process.exit(1);
}
ROOT = path.resolve(ROOT);

// --- kit.yaml flat-key 宣告解析（與 kit_decl_get 同語意）--------------------

/** _kit_unquote_value 的 TS 對照：成對引號取引號內、未引號去「空白+#」註解再去尾空白。 */
function unquoteValue(raw: string): string {
  if (raw.startsWith('"')) {
    const rest = raw.slice(1);
    const end = rest.indexOf('"');
    return end >= 0 ? rest.slice(0, end) : rest;
  }
  if (raw.startsWith("'")) {
    const rest = raw.slice(1);
    const end = rest.indexOf("'");
    return end >= 0 ? rest.slice(0, end) : rest;
  }
  let val = raw.replace(/^#.*$/, "").replace(/[ \t]#.*$/, "");
  val = val.replace(/\s+$/, "");
  return val;
}

/**
 * kit_decl_get 的 TS 對照（兩態語意，與 lib/common.sh 同構，改動必兩側同改）：
 * key 存在但值為空（`key: ""` 或 `key:` 後無值）→ 回空字串（欄位留空＝降級，
 * 不吃 default）；key 完全缺席／檔案缺失 → 回 default（fail-open）。
 */
function declGet(file: string, key: string, dflt: string): string {
  let text: string;
  try {
    text = fs.readFileSync(file, "utf8");
  } catch {
    return dflt;
  }
  for (const line of text.split("\n")) {
    const m = line.match(new RegExp(`^${key}:[ \\t]*(.*)$`));
    if (m) {
      return unquoteValue(m[1]);
    }
  }
  return dflt;
}

const KIT_YAML = declDirOverride ? path.join(declDirOverride, "kit.yaml") : path.join(ROOT, ".claude/kit/kit.yaml");
const splitWs = (s: string): string[] => s.split(/\s+/).filter(Boolean);

const MATRIX_DIR_REL = declGet(KIT_YAML, "matrix_dir", "docs/rtm/matrix").replace(/\/+$/, "");
const MATRIX_DIR = path.join(ROOT, MATRIX_DIR_REL);
const VALID_STATUS = splitWs(declGet(KIT_YAML, "status_enum", "implemented partial divergent planned na"));
const NOTES_REQUIRED = splitWs(declGet(KIT_YAML, "rtm_notes_required", "divergent"));
const SPECS_REQUIRED = splitWs(declGet(KIT_YAML, "rtm_detail_specs_required", "implemented partial divergent"));
const IMPL_REQUIRED = splitWs(declGet(KIT_YAML, "rtm_impl_details_required", "implemented partial"));
// "." 表 repo 根（宣告檔不便表達空字串；上游 FALLBACK_BASES 的 "" 對應 "."）
const FALLBACK_BASES = splitWs(declGet(KIT_YAML, "impl_path_bases", ".")).map((b) => (b === "." ? "" : b));
const KNOWN_NON_PATH_TOKENS = new Set(splitWs(declGet(KIT_YAML, "rtm_nonpath_tokens", "Next.js Node.js")));

// --- js-yaml：createRequire 從目標專案 node_modules 解析（kit 零 node 依賴）---

let yamlLoad: (s: string) => unknown;
try {
  const projectRequire = createRequire(pathToFileURL(path.join(ROOT, "package.json")));
  const yaml = projectRequire("js-yaml") as { load: (s: string) => unknown };
  yamlLoad = yaml.load;
} catch {
  console.error(
    `rtm-check: 無法從目標專案解析 js-yaml（解析基準 ${path.join(ROOT, "package.json")}）——` +
      "rtm 模組要求專案自備 js-yaml，請在專案安裝後重跑",
  );
  process.exit(1);
}

interface MatrixEntry {
  req_id?: string;
  rfp_id?: string;
  req_text?: string;
  rfp_text?: string;
  status: string;
  detail_specs?: string[];
  impl_routes?: string[];
  impl_details?: string[];
  notes?: string;
  last_discussed?: string;
  verify?: string;
}
interface MatrixFile {
  meta?: { section?: string; total_clauses?: number };
  entries: MatrixEntry[];
}

// --- impl_details 路徑存在性檢查（check 7，逐位保留上游抽取邏輯）------------

const CODE_EXTS = ["tsx", "ts", "yaml", "yml", "json", "mjs", "js", "md", "sql", "prisma"] as const;
const EXT_ALT = CODE_EXTS.join("|");
// 一段連續的「路徑字元」（不含全形標點、括號、逗號、大括號、星號——這些字元
// 天然把 model 名稱列表／glob／brace 展開跟真正的檔案路徑切開）
const RUN_RE = /[A-Za-z0-9_.\-/[\]]+/g;
const BOUNDARY_RE = new RegExp(`\\.(?:${EXT_ALT})(?=/|$)`, "g");
const LINE_REF_RE = /^[:：](\d+)(?:-(\d+))?/;

interface PathCandidate {
  candidate: string;
  lineRef?: string;
}

/** 從一段自由文字中抽出看起來像檔案路徑的候選字串（含行號後綴，若有）。 */
function extractPathCandidates(text: string): PathCandidate[] {
  const results: PathCandidate[] = [];
  RUN_RE.lastIndex = 0;
  let m: RegExpExecArray | null;
  while ((m = RUN_RE.exec(text))) {
    const run = m[0];
    const runStart = m.index;
    BOUNDARY_RE.lastIndex = 0;
    const boundaries: number[] = [];
    let b: RegExpExecArray | null;
    while ((b = BOUNDARY_RE.exec(run))) boundaries.push(b.index + b[0].length);
    let segStart = 0;
    for (const boundaryEnd of boundaries) {
      const raw = run.slice(segStart, boundaryEnd);
      const candidate = raw.replace(/^\/+/, "");
      const lastSeg = candidate.slice(candidate.lastIndexOf("/") + 1);
      const dotIdx = lastSeg.lastIndexOf(".");
      const isAtEnd = boundaryEnd === run.length;
      segStart = !isAtEnd && run[boundaryEnd] === "/" ? boundaryEnd + 1 : boundaryEnd;
      if (dotIdx <= 0) continue; // 空 stem（例如 glob 殘留的 ".yaml"）——不是真檔名
      if (lastSeg.startsWith("-")) continue; // brace 展開殘留——不是真檔名
      if (KNOWN_NON_PATH_TOKENS.has(candidate)) continue;
      let lineRef: string | undefined;
      if (isAtEnd) {
        const after = text.slice(runStart + run.length);
        const lr = LINE_REF_RE.exec(after);
        if (lr) lineRef = lr[0];
      }
      results.push({ candidate, lineRef });
    }
  }
  return results;
}

let trackedFilesCache: string[] | null = null;
function loadTrackedFiles(): string[] {
  if (trackedFilesCache) return trackedFilesCache;
  try {
    const out = execFileSync("git", ["ls-files"], { cwd: ROOT, encoding: "utf8" });
    trackedFilesCache = out.split("\n").filter(Boolean);
  } catch {
    trackedFilesCache = [];
  }
  return trackedFilesCache;
}

/** candidate 對應到的全部真實檔案（repo-root 相對路徑）。空陣列＝不存在。
 *  上游 candidateExists 的一對多版：--emit-index 需要全部解析結果，
 *  存在性判定（length > 0）與上游語意等價。 */
function resolveCandidate(candidate: string): string[] {
  const tracked = loadTrackedFiles();
  const hits = tracked.filter((p) => p === candidate || p.endsWith("/" + candidate));
  if (hits.length > 0) return hits;
  const out: string[] = [];
  for (const base of FALLBACK_BASES) {
    const abs = path.join(ROOT, base, candidate);
    if (fs.existsSync(abs)) out.push(path.relative(ROOT, abs));
  }
  return Array.from(new Set(out));
}

function fail(msgs: string[]): never {
  for (const m of msgs.slice(0, 25)) console.error(`rtm-check: ${m}`);
  if (msgs.length > 25) console.error(`rtm-check: …共 ${msgs.length} 項違規`);
  process.exit(1);
}

// --- 主檢查迴圈 ------------------------------------------------------------

if (!fs.existsSync(MATRIX_DIR)) fail([`找不到 ${MATRIX_DIR}`]);
const files = fs
  .readdirSync(MATRIX_DIR)
  .filter((f) => f.endsWith(".yaml"))
  .sort();
if (files.length === 0) fail([`${MATRIX_DIR_REL}/ 內無 yaml 檔`]);

const errors: string[] = [];
const globalIds = new Map<string, string>(); // req_id -> file
const counts: Record<string, number> = {};
let totalEntries = 0;
let discussed = 0;
let pathCandidatesTotal = 0;
let pathCandidatesOk = 0;
let pathCandidatesMissing = 0;
const indexRows = new Set<string>(); // "<resolved>\t<req_id>\t<matrix 檔名>"

for (const f of files) {
  const p = path.join(MATRIX_DIR, f);
  let doc: MatrixFile;
  try {
    doc = yamlLoad(fs.readFileSync(p, "utf8")) as MatrixFile;
  } catch (e) {
    errors.push(`${f}: YAML 解析失敗：${(e as Error).message}`);
    continue;
  }
  if (!Array.isArray(doc?.entries) || doc.entries.length === 0) {
    errors.push(`${f}: 缺 entries 陣列或為空`);
    continue;
  }
  const total = doc.meta?.total_clauses;
  if (typeof total !== "number") {
    errors.push(`${f}: meta.total_clauses 缺失（per-file 條文守恆錨）`);
  } else if (total !== doc.entries.length) {
    errors.push(`${f}: 條文守恆失敗 meta.total_clauses=${total} ≠ entries ${doc.entries.length}（增刪條目須同步 meta）`);
  }
  const section = doc.meta?.section ?? "";

  for (const e of doc.entries) {
    totalEntries++;
    const reqId = e.req_id ?? e.rfp_id ?? "";
    const reqText = e.req_text ?? e.rfp_text ?? "";
    if (!reqId.trim()) { errors.push(`${f}: 有 entry 缺 req_id`); continue; }
    const prev = globalIds.get(reqId);
    if (prev) errors.push(`${reqId}: 跨檔重複（${prev} 與 ${f}）`);
    globalIds.set(reqId, f);
    if (section && !reqId.startsWith(section))
      errors.push(`${f}: ${reqId} 前綴與 meta.section「${section}」不符`);
    if (!VALID_STATUS.includes(e.status)) { errors.push(`${reqId}: 非法 status「${e.status}」`); continue; }
    counts[e.status] = (counts[e.status] ?? 0) + 1;
    if (!reqText.trim()) errors.push(`${reqId}: req_text 空`);
    if (NOTES_REQUIRED.includes(e.status) && !e.notes?.trim())
      errors.push(`${reqId}: ${e.status} 但 notes 空——差異必須寫明`);
    if (SPECS_REQUIRED.includes(e.status) && (!e.detail_specs || e.detail_specs.length === 0))
      errors.push(`${reqId}: status=${e.status} 但 detail_specs 空`);
    if (IMPL_REQUIRED.includes(e.status) && (!e.impl_details || e.impl_details.length === 0))
      errors.push(`${reqId}: status=${e.status} 但 impl_details 空——缺 code 定位錨點`);
    if (e.last_discussed) discussed++;

    for (const detail of e.impl_details ?? []) {
      for (const { candidate, lineRef } of extractPathCandidates(detail)) {
        pathCandidatesTotal++;
        const resolved = resolveCandidate(candidate);
        if (resolved.length > 0) {
          pathCandidatesOk++;
          for (const r of resolved) indexRows.add(`${r}\t${reqId}\t${f}`);
        } else {
          pathCandidatesMissing++;
          errors.push(
            `${reqId}: impl_details 路徑失準——「${candidate}${lineRef ?? ""}」找不到對應檔案（${f}）`,
          );
        }
      }
    }
  }
}

if (errors.length > 0) fail(errors);

// --- --emit-index：檢查全綠後才寫（紅燈不產 index，避免半錯反查表）----------

if (emitIndex) {
  const h = crypto.createHash("sha256");
  for (const f of files) h.update(fs.readFileSync(path.join(MATRIX_DIR, f)));
  const matrixHash = h.digest("hex");
  const idxDir = path.join(ROOT, ".claude/kit");
  fs.mkdirSync(idxDir, { recursive: true });
  const rows = Array.from(indexRows).sort();
  fs.writeFileSync(
    path.join(idxDir, "rtm-index.tsv"),
    `# rtm-index v1 matrix_hash=sha256:${matrixHash}\n` + rows.map((r) => r + "\n").join(""),
  );
  console.log(`rtm-check: index → .claude/kit/rtm-index.tsv（${rows.length} 列映射）`);
}

const statLine = VALID_STATUS.map((s) => `${s}=${counts[s] ?? 0}`).join(" ");
console.log(
  `rtm-check: PASS — ${files.length} 檔 ${totalEntries} 條｜${statLine}｜已與承辦人對齊 ${discussed} 條｜` +
    `impl_details 路徑 ${pathCandidatesTotal} 個（存在 ${pathCandidatesOk}／缺失 ${pathCandidatesMissing}）`,
);
