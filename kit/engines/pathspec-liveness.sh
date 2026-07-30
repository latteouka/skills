#!/usr/bin/env bash
# engines/pathspec-liveness.sh — 宣告掃描目標內 git pathspec 存活檢查
# （消費 <decl-dir>/pathspec-targets.conf）。
#
# 吸收自 dfaa scripts/hooks/pathspec-liveness.sh：掃描對象由硬編碼
# （.husky/* + scripts/hooks/*.sh）改為讀專案宣告檔，解析與檢查邏輯
# （awk 解析器、cd 追蹤、恆 0 偵測、白名單）逐位元組保留。
#
# 背景（這支 script 存在的唯一理由，見上游 dfaa commit 7c904ee47）：
#   .husky/pre-push 第一行 `cd apps/web`，而 git pathspec 預設是 **cwd 相對**。
#   當年 pathspec 寫成 repo-root 相對的 'apps/web/src/**/*.tsx'，被解成
#   apps/web/apps/web/src/**/*.tsx——恆 0 命中。於是每段條件判斷都拿到空字串，
#   typecheck／lint／測試／lockfile 校驗全部靜默跳過——空轉 8 天（測試自
#   3585a1699 2026-07-17、typecheck/lint/lockfile 自 6c56f2531 2026-07-20），
#   期間每次 push 都是綠燈。修法是給每條 pathspec 加 `:(top)` magic 錨 repo
#   root。但修完沒有機制防止下次再寫錯——本 script 就是那個機制。
#
# 用法：
#   bash engines/pathspec-liveness.sh [--decl-dir <path>] [--repo-root <path>]
#     --decl-dir   宣告目錄，預設 <repo>/.claude/kit（測試 seam）
#     --repo-root  受檢 repo root，預設 git rev-parse --show-toplevel（測試 seam）
#
# 掃描目標宣告（<decl-dir>/pathspec-targets.conf）：
#   每行一個 repo-root 相對路徑；`#` 開頭為註解行；空行跳過。
#     - 檔案行：掃該檔。依副檔名分派解析器——`.sh` → script 形態（處理
#       `(cd … && git diff)` 子 shell、literal wrapper、literal 變數展開），
#       其餘（如無副檔名的 husky hook）→ hook 形態（頂層循序 cd 追蹤）。
#       與上游分派一致：上游 .husky/*（無副檔名）走 hook 形態、
#       scripts/hooks/*.sh 走 script 形態。
#     - 目錄行：掃該目錄下全部 *.sh（script 形態）。
#
# 協定：
#   逐一掃描宣告目標，解析每一條 `git diff ... -- <pathspec...>` 的 pathspec
#   引數，對每條在「該 hook 實際執行到這一行時的 cwd」下跑
#   `git ls-files -- <pathspec>`，斷言輸出 ≥1 行。任一條恆 0 命中 → exit 1，
#   逐條列出「檔案:行號、pathspec、命中數」。
#
#   為什麼不是「一律在 repo root 測」：`:(top)` magic 本身就是 cwd 無關的
#   （這正是修法的原理），但驗證這件事本身，必須在「pathspec 沒加 magic」
#   時仍然抓得到歷史那個 bug——而那個 bug 的成因正是 cwd=apps/web（pre-push
#   第一行 cd 進去）。若本 script 永遠固定在 repo root 測，反向驗證（拿掉
#   :(top)）會失敗：'apps/web/src/**/*.ts' 從 repo root 測剛好還是對的
#   （字面上就是正確的 root-relative 路徑），只有從 apps/web 測才會重現
#   「apps/web/apps/web/...」的恆 0 命中。因此本 script 會追蹤每支 hook
#   檔內、在每個 git diff pathspec 區塊「之前」出現過的 `cd` 命令（用真實
#   `cd + pwd` 解析相對路徑，不手刻路徑運算），把每條 pathspec 放到「這支
#   hook 真的會用哪個 cwd 執行它」下面去測。git 呼叫 hook 時的起始 cwd
#   固定是 repo root（標準 git 行為），故每支 hook 檔案都從 repo root 開始
#   往下追蹤。
#
#   fail-closed（閘門，不是回饋層，比照上游 ratchet.sh）：
#     - repo root 無法定位、pathspec-targets.conf 缺失或無有效目標、conf 列的
#       檔案或目錄不存在、目錄行內無 *.sh、pathspec 解析失敗（含格式無法辨識、
#       cd 目標無法解析）→ exit 1，不當成「沒有問題」——防假 0 的引擎自己
#       不能假 0。
#     - 任一條 pathspec 恆 0 命中且未在白名單 → exit 1。
#   exit 語意：0 = 全部命中；1 = 有恆 0 命中的 pathspec 或解析/前置檢查失敗。
#   stdout 恆印 inspected:N（N = 本輪實際檢查的 pathspec 條數；kit 化新增，
#   對接 canary 三斷言之 3——「跑了但檢查 0 條」與全綠必須可區分的同款母題；
#   上游同一資訊表達在 PASS 訊息內的條數）。
#
#   白名單：極少數 pathspec 現況合法但目前 0 命中（例如指向暫時空的目錄）。
#   每條白名單必須附理由（whitelist_reason() 內的 case 分支），且會印在輸出
#   裡（不是靜默跳過）。2026-07-25 上游實測全部 13 條唯一 pathspec（22 次出現）
#   皆 ≥1 命中（含 ':(top)patches/' 命中 2 檔），故目前白名單為空。
#
# bash 3.2 相容（macOS 內建版本）：
#   禁 declare -A／${var,,}／mapfile／readarray。set -u 下一律用 ${var}
#   大括號形式——裸 $var 緊接全形標點會誤判 unbound variable 並中止整支
#   script（上游 ratchet.sh 同款陷阱）。白名單用 case 陳述式而非關聯陣列。

set -u
set -o pipefail

# ---------- 參數（測試 seam） ----------

DECL_DIR=""
REPO_ROOT_ARG=""
while [ $# -gt 0 ]; do
  case "${1}" in
    --decl-dir)
      [ $# -ge 2 ] || { echo "pathspec-liveness: --decl-dir 缺參數值" >&2; exit 1; }
      DECL_DIR="${2}"; shift 2 ;;
    --repo-root)
      [ $# -ge 2 ] || { echo "pathspec-liveness: --repo-root 缺參數值" >&2; exit 1; }
      REPO_ROOT_ARG="${2}"; shift 2 ;;
    *)
      echo "pathspec-liveness: 未知參數 [${1}]，fail-closed，拒絕通過" >&2
      exit 1 ;;
  esac
done

# ---------- 前置：定位 repo root（worktree 相容，不假設 cwd） ----------

if [ -n "${REPO_ROOT_ARG}" ]; then
  PROJECT_ROOT="$(cd "${REPO_ROOT_ARG}" 2>/dev/null && pwd -P)"
  if [ -z "${PROJECT_ROOT}" ]; then
    echo "pathspec-liveness: --repo-root 目錄不存在 [${REPO_ROOT_ARG}]，fail-closed，拒絕通過" >&2
    exit 1
  fi
else
  PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
  if [ -z "${PROJECT_ROOT}" ]; then
    echo "pathspec-liveness: 不在 git 工作目錄內，fail-closed，拒絕通過" >&2
    exit 1
  fi
fi

if [ -z "${DECL_DIR}" ]; then
  DECL_DIR="${PROJECT_ROOT}/.claude/kit"
fi
TARGETS_CONF="${DECL_DIR}/pathspec-targets.conf"

if [ ! -f "${TARGETS_CONF}" ]; then
  echo "pathspec-liveness: 掃描目標宣告檔不存在 [${TARGETS_CONF}]，fail-closed，拒絕通過" >&2
  exit 1
fi

# ---------- 白名單（見上方協定說明；目前為空） ----------
#
# 新增白名單時：在下面 case 分支加一行 `':(top)xxx') printf '理由'; return 0 ;;`，
# 理由必須說明「為什麼這條 pathspec 現在合法地 0 命中」（例如：功能尚未落地、
# 目錄刻意暫空等），不得只寫「已知」二字帶過。
whitelist_reason() {
  local pathspec="${1}"
  case "${pathspec}" in
    *)
      return 1
      ;;
  esac
}

# ---------- awk 解析器（單一 hook 檔 → CD:/TOKEN:/PARSE_ERROR: 事件流） ----------
#
# 輸出格式（依檔案原始行序，逐行印一個事件）：
#   CD:<lineno>:<target>       — 偵測到一條 `cd <target>` 陳述式（僅在未於
#                                 pathspec 引數清單中時偵測；heuristic：該行
#                                 第一個空白分隔欄位恰為 "cd"，不理解
#                                 子殼層/條件式——上游現行三支 hook 檔皆為
#                                 頂層循序 cd，符合此假設）
#   TOKEN:<lineno>:<pathspec>  — 偵測到一條 pathspec 引數（單引號字串，緊接在
#                                 `git diff ... -- ` 之後、或接續上一行的
#                                 反斜線續行）
#   PARSE_ERROR:<lineno>:<原因> — 格式無法辨識（例如未閉合的單引號），awk
#                                 以 exit 2 中止，bash 端一律 fail-closed
#
# pathspec 引數清單的判定：從 `git diff` 那行找到獨立的 "--" 欄位開始，
# 之後每個欄位若以單引號開頭且以單引號結尾即視為一條 pathspec；一遇到不是
# 單引號包起來的欄位（例如 2>/dev/null）就視為清單結束（這正是用來避開
# 「-- 'a' 'b' 2>/dev/null | sed 's|x|y|'」這種後面接 sed 單引號參數的陷阱：
# 一旦遇到 2>/dev/null 就停止收集，不會誤把 sed 的 's|x|y|' 當成 pathspec）。
# 反斜線續行（行尾恰為 "\" 一個獨立欄位）會延續到下一行繼續收集。
parse_hook_file() {
  local file="${1}"
  awk -f - "${file}" <<'AWK_EOF'
{
  lineno = FNR
  n = NF
  continues = 0
  eff_n = n
  if (n >= 1 && $n == "\\") {
    continues = 1
    eff_n = n - 1
  }

  if (!capturing && eff_n >= 2 && $1 == "cd") {
    print "CD:" lineno ":" $2
    next
  }

  start = 1
  if (!capturing) {
    if (index($0, "git diff") > 0) {
      sep = 0
      for (i = 1; i <= eff_n; i++) {
        if ($i == "--") { sep = i; break }
      }
      if (sep > 0) {
        capturing = 1
        start = sep + 1
      } else {
        next
      }
    } else {
      next
    }
  }

  for (i = start; i <= eff_n; i++) {
    tok = $i
    tlen = length(tok)
    if (substr(tok, 1, 1) == "'") {
      if (tlen >= 2 && substr(tok, tlen, 1) == "'") {
        val = substr(tok, 2, tlen - 2)
        if (val == "") {
          print "PARSE_ERROR:" lineno ":empty-pathspec-token"
          exit 2
        }
        print "TOKEN:" lineno ":" val
      } else {
        print "PARSE_ERROR:" lineno ":malformed-quoted-token:" tok
        exit 2
      }
    } else {
      capturing = 0
      break
    }
  }

  if (capturing == 1 && continues != 1) {
    capturing = 0
  }
}
AWK_EOF
}

# 上游 scripts/hooks 的真實形態：`(cd … && git diff)` 子 shell、ratchet 的
# no_relevant_changes literal wrapper、以及 UI_GLOB literal 變數來源。
parse_script_hook_file() {
  local file="${1}"
  awk -f - "${file}" <<'AWK_EOF'
function emit(tok, line, kind, subdir, rest, q, val) {
  if (substr(tok, 1, 1) != "'") return 0
  rest = substr(tok, 2); q = index(rest, "'")
  if (q == 0) { print "PARSE_ERROR:" line ":malformed-token:" tok; exit 2 }
  val = substr(rest, 1, q - 1)
  if (kind == "SUB") print "SUB_TOKEN:" line ":" subdir ":" val
  else print "ROOT_TOKEN:" line ":" val
  return 1
}
{
  trimmed = $0; sub(/^[ \t]+/, "", trimmed)
  if (trimmed == "" || substr(trimmed, 1, 1) == "#") next
  if (match(trimmed, /^[A-Za-z_][A-Za-z0-9_]*='[^']*'$/)) {
    eq = index(trimmed, "="); name = substr(trimmed, 1, eq - 1)
    vars[name] = substr(trimmed, eq + 2, length(trimmed) - eq - 2); next
  }
  if (trimmed ~ /^no_relevant_changes[ \t]+/) {
    for (i = 2; i <= NF; i++) emit($i, FNR, "ROOT", "")
    next
  }
  git_i = 0
  for (i = 1; i <= NF; i++) if ($i == "git" || $i ~ /\(git$/) { git_i = i; break }
  if (git_i == 0) next
  kind = "ROOT"; subdir = ""
  if (git_i >= 4 && $(git_i - 1) == "&&" && $(git_i - 3) ~ /\(cd$/) {
    target = $(git_i - 2)
    if (target !~ /^"\$\{(root|PROJECT_ROOT|project_dir)\}"$/) {
      gsub(/^["']|["']$/, "", target); kind = "SUB"; subdir = target
    }
  }
  sep = 0
  for (i = git_i + 1; i <= NF; i++) if ($i == "--") { sep = i; break }
  if (sep == 0) next
  for (i = sep + 1; i <= NF; i++) {
    if (emit($i, FNR, kind, subdir)) continue
    if (substr($i, 1, 3) == "\"${") {
      close_pos = index($i, "}\""); if (close_pos == 0) next
      name = substr($i, 4, close_pos - 4); if (name == "@") next
      if (!(name in vars)) { print "PARSE_ERROR:" FNR ":unresolved-variable:" name; exit 2 }
      if (kind == "SUB") print "SUB_TOKEN:" FNR ":" subdir ":" vars[name]
      else print "ROOT_TOKEN:" FNR ":" vars[name]
      continue
    }
    break
  }
}
AWK_EOF
}

inspect_pathspec() {
  local source_name="${1}" t_lineno="${2}" pathspec="${3}" token_abs_dir="${4}"
  local ls_out ls_rc hits cwd_rel reason
  grand_total=$((grand_total + 1))
  target_pathspec_count=$((target_pathspec_count + 1))
  ls_out="$(cd "${token_abs_dir}" && git ls-files -- "${pathspec}" 2>&1)"; ls_rc=$?
  [ "${ls_rc}" -eq 0 ] || return 2
  if [ -z "${ls_out}" ]; then hits=0; else hits="$(printf '%s\n' "${ls_out}" | wc -l | tr -d ' ')"; fi
  cwd_rel="${token_abs_dir#"${PROJECT_ROOT}"/}"; [ "${cwd_rel}" = "${token_abs_dir}" ] && cwd_rel="."
  if [ "${hits}" -eq 0 ]; then
    reason=""
    if reason="$(whitelist_reason "${pathspec}")"; then
      printf '  %s:%-4s %-45s hits=0  WHITELISTED（%s，cwd=%s）\n' "${source_name}" "${t_lineno}" "${pathspec}" "${reason}" "${cwd_rel}"
    else
      printf '  %s:%-4s %-45s hits=0  FAIL（cwd=%s）\n' "${source_name}" "${t_lineno}" "${pathspec}" "${cwd_rel}"
      fail_count=$((fail_count + 1)); fail_report="${fail_report}${source_name}:${t_lineno}"$'\t'"${pathspec}"$'\t'"hits=0（cwd=${cwd_rel}）"$'\n'
    fi
  else
    printf '  %s:%-4s %-45s hits=%s  OK\n' "${source_name}" "${t_lineno}" "${pathspec}" "${hits}"
  fi
}

# ---------- 展開掃描目標（conf → 「形態<TAB>repo 相對路徑」清單；先全驗再掃） ----------
#
# 形態：hook = 頂層循序 cd 追蹤解析器；script = (cd … && git diff) 子 shell
# 解析器。分派規則見檔頭「掃描目標宣告」節。全部展開並驗證存在後才開始掃，
# 任一條宣告失效即 fail-closed，不做半套。

TARGET_LIST=""
target_count=0
conf_lineno=0
while IFS= read -r conf_line || [ -n "${conf_line}" ]; do
  conf_lineno=$((conf_lineno + 1))
  # 去頭尾空白；跳過空行與 # 開頭註解行
  entry="${conf_line#"${conf_line%%[![:space:]]*}"}"
  entry="${entry%"${entry##*[![:space:]]}"}"
  case "${entry}" in
    ''|'#'*) continue ;;
  esac
  case "${entry}" in
    /*)
      echo "pathspec-liveness: conf:${conf_lineno} 只接受 repo-root 相對路徑 [${entry}]，fail-closed，拒絕通過" >&2
      exit 1
      ;;
  esac
  abs_entry="${PROJECT_ROOT}/${entry}"
  if [ -d "${abs_entry}" ]; then
    dir_found=0
    for f in "${abs_entry}"/*.sh; do
      [ -f "${f}" ] || continue
      # 上游行為保留：目錄掃描排除引擎自身檔名（上游把自己排除在
      # scripts/hooks glob 之外；專案若 vendor 一份同名引擎進掃描目錄，
      # 掃它只會解析到引擎自己的 awk heredoc，無意義）
      [ "$(basename "${f}")" = "pathspec-liveness.sh" ] && continue
      dir_found=1
      rel="${f#"${PROJECT_ROOT}"/}"
      TARGET_LIST="${TARGET_LIST}script"$'\t'"${rel}"$'\t'"lax"$'\n'
      target_count=$((target_count + 1))
    done
    if [ "${dir_found}" -eq 0 ]; then
      echo "pathspec-liveness: conf:${conf_lineno} 目錄內無可掃描的 *.sh [${entry}]，fail-closed，拒絕通過" >&2
      exit 1
    fi
  elif [ -f "${abs_entry}" ]; then
    case "${entry}" in
      *.sh) target_form="script" ;;
      *)    target_form="hook" ;;
    esac
    TARGET_LIST="${TARGET_LIST}${target_form}"$'\t'"${entry}"$'\t'"strict"$'\n'
    target_count=$((target_count + 1))
  else
    echo "pathspec-liveness: conf:${conf_lineno} 列的路徑不存在 [${entry}]（展開為 ${abs_entry}），fail-closed，拒絕通過" >&2
    exit 1
  fi
done < "${TARGETS_CONF}"

if [ "${target_count}" -eq 0 ]; then
  echo "pathspec-liveness: 宣告檔無任何有效掃描目標 [${TARGETS_CONF}]，fail-closed，拒絕通過" >&2
  exit 1
fi

# ---------- 主流程 ----------

grand_total=0
fail_count=0
fail_report=""

while IFS=$'\t' read -r target_form target_rel target_strict || [ -n "${target_form}" ]; do
  [ -z "${target_form}" ] && continue
  hook_file="${PROJECT_ROOT}/${target_rel}"
  # 目標層計數器（GPT-5 總檢 §4.4 裁定）：目標存在但解析出 0 條 pathspec 是假
  # 0——不能靜默通過。每個目標獨立歸零、獨立判定。
  target_pathspec_count=0

  if [ "${target_form}" = "hook" ]; then

  hook_name="${target_rel}"
  if [ ! -f "${hook_file}" ]; then
    echo "pathspec-liveness: 找不到 hook 檔 [${hook_file}]，fail-closed，拒絕通過" >&2
    exit 1
  fi

  parse_out="$(parse_hook_file "${hook_file}")"
  parse_rc=$?
  if [ "${parse_rc}" -ne 0 ]; then
    echo "pathspec-liveness: 解析 [${hook_name}] 失敗（awk exit=${parse_rc}），fail-closed，拒絕通過" >&2
    printf '%s\n' "${parse_out}" | grep '^PARSE_ERROR:' | sed 's/^/  /' >&2
    exit 1
  fi

  echo "--- ${hook_name} ---"

  current_abs_dir="${PROJECT_ROOT}"

  while IFS= read -r ev || [ -n "${ev}" ]; do
    [ -z "${ev}" ] && continue
    case "${ev}" in
      CD:*)
        rest="${ev#CD:}"
        cd_lineno="${rest%%:*}"
        cd_target="${rest#*:}"
        new_dir="$(cd "${current_abs_dir}/${cd_target}" 2>/dev/null && pwd)"
        if [ -z "${new_dir}" ]; then
          echo "pathspec-liveness: [${hook_name}:${cd_lineno}] cd 目標無法解析 [${cd_target}]（現行 cwd=${current_abs_dir}），fail-closed，拒絕通過" >&2
          exit 1
        fi
        current_abs_dir="${new_dir}"
        ;;
      TOKEN:*)
        rest="${ev#TOKEN:}"
        t_lineno="${rest%%:*}"
        pathspec="${rest#*:}"

        grand_total=$((grand_total + 1))
        target_pathspec_count=$((target_pathspec_count + 1))

        # 明確驗 git ls-files 自己的 exit code（不只信輸出行數）——ERRATA 鐵則
        # 2：計數拿到 0 前先驗 exit code，否則 git 本身出錯（例如 magic 語法
        # 無法辨識）會被誤讀成「合法的 0 命中」而漏判，甚至讓 hits 變成空字串
        # 使下面 `-eq 0` 比較噴錯後意外落到 OK 分支（fail-open）。
        ls_out="$(cd "${current_abs_dir}" && git ls-files -- "${pathspec}" 2>&1)"
        ls_rc=$?
        if [ "${ls_rc}" -ne 0 ]; then
          echo "pathspec-liveness: [${hook_name}:${t_lineno}] git ls-files 執行失敗（exit=${ls_rc}）pathspec=[${pathspec}] cwd=${current_abs_dir}，fail-closed，拒絕通過：" >&2
          printf '%s\n' "${ls_out}" | sed 's/^/    /' >&2
          exit 1
        fi
        if [ -z "${ls_out}" ]; then
          hits=0
        else
          hits="$(printf '%s\n' "${ls_out}" | wc -l | tr -d ' ')"
        fi

        cwd_rel="${current_abs_dir#"${PROJECT_ROOT}"/}"
        [ "${cwd_rel}" = "${current_abs_dir}" ] && cwd_rel="."

        if [ "${hits}" -eq 0 ]; then
          reason=""
          if reason="$(whitelist_reason "${pathspec}")"; then
            printf '  %s:%-4s %-45s hits=0  WHITELISTED（%s，cwd=%s）\n' "${hook_name}" "${t_lineno}" "${pathspec}" "${reason}" "${cwd_rel}"
          else
            printf '  %s:%-4s %-45s hits=0  FAIL（cwd=%s）\n' "${hook_name}" "${t_lineno}" "${pathspec}" "${cwd_rel}"
            fail_count=$((fail_count + 1))
            fail_report="${fail_report}${hook_name}:${t_lineno}"$'\t'"${pathspec}"$'\t'"hits=0（cwd=${cwd_rel}）"$'\n'
          fi
        else
          printf '  %s:%-4s %-45s hits=%s  OK\n' "${hook_name}" "${t_lineno}" "${pathspec}" "${hits}"
        fi
        ;;
      *)
        echo "pathspec-liveness: [${hook_name}] 未知事件格式 [${ev}]，fail-closed，拒絕通過" >&2
        exit 1
        ;;
    esac
  done <<< "${parse_out}"

  else

  source_name="${hook_file#"${PROJECT_ROOT}"/}"
  parse_out="$(parse_script_hook_file "${hook_file}")"
  parse_rc=$?
  [ "${parse_rc}" -eq 0 ] || { echo "pathspec-liveness: 解析 [${source_name}] 失敗" >&2; exit 1; }
  # 注意：不對空 parse_out 提前 continue——目標存在但解析出 0 條 pathspec
  # 本身就是待判定的情況（見下方目標層 0 條檢查），不能靜默略過整個目標。
  if [ -n "${parse_out}" ]; then
    echo "--- ${source_name} ---"
    while IFS= read -r ev || [ -n "${ev}" ]; do
      case "${ev}" in
        ROOT_TOKEN:*)
          rest="${ev#ROOT_TOKEN:}"
          t_lineno="${rest%%:*}"
          pathspec="${rest#*:}"
          inspect_pathspec "${source_name}" "${t_lineno}" "${pathspec}" "${PROJECT_ROOT}" || exit 1
          ;;
        SUB_TOKEN:*)
          rest="${ev#SUB_TOKEN:}"
          t_lineno="${rest%%:*}"
          rest="${rest#*:}"
          subdir="${rest%%:*}"
          pathspec="${rest#*:}"
          token_abs_dir="$(cd "${PROJECT_ROOT}/${subdir}" 2>/dev/null && pwd)"
          [ -n "${token_abs_dir}" ] || exit 1
          inspect_pathspec "${source_name}" "${t_lineno}" "${pathspec}" "${token_abs_dir}" || exit 1
          ;;
        *) echo "pathspec-liveness: [${source_name}] 未知事件 [${ev}]" >&2; exit 1 ;;
      esac
    done <<< "${parse_out}"
  fi

  fi

  # 目標層 0 條判定（GPT-5 總檢 §4.4 裁定）：這個目標從頭到尾一條 pathspec
  # 都沒解析出來，是假 0（跟「解析成功、只是巧合 0 個 git diff 呼叫」在使用者
  # 眼中無法區分）——一律當成 FAIL，訊息點名來源檔與零條指示，不靜默放行。
  # lax（目錄展開檔）豁免：上游語意是「掃目錄、無 pathspec 的 hook 靜默跳過」
  # ——每支 hook 都有 pathspec 不是宣告者的承諾；strict（conf 明示檔案）才是。
  # 目錄整體死 glob 已在展開處 fail-closed；全域 inspected:0 兜底不變量仍在。
  if [ "${target_pathspec_count}" -eq 0 ] && [ "${target_strict:-strict}" = "strict" ]; then
    echo "pathspec-liveness: [${target_rel}] 解析出 0 條 pathspec（宣告目標存在但無可驗證內容，防假 0），FAIL" >&2
    fail_count=$((fail_count + 1))
    fail_report="${fail_report}${target_rel}"$'\t'"(none)"$'\t'"解析出 0 條 pathspec"$'\n'
  fi
done <<< "${TARGET_LIST}"

echo ""
echo "inspected:${grand_total}"

# 兜底不變量（GPT-5 總檢 §4.4 裁定）：inspected:0 與 exit 0 絕不並存。上面的
# 目標層 0 條檢查應已在 grand_total 有機會歸零前攔下所有已知路徑，但這條
# 檢查獨立存在、不依賴上面的邏輯——未來若解析協定改版漏掉某個路徑，這裡仍
# 會 fail-closed，不讓「跑了但什麼都沒檢查到」偽裝成綠燈。
if [ "${grand_total}" -eq 0 ]; then
  echo "pathspec-liveness: inspected:0（本輪未實際檢查任何 pathspec），fail-closed，拒絕通過" >&2
  exit 1
fi

if [ "${fail_count}" -gt 0 ]; then
  echo "pathspec-liveness: FAIL -- ${fail_count} 條 pathspec 恆 0 命中：" >&2
  printf '%s' "${fail_report}" | while IFS=$'\t' read -r loc spec detail; do
    echo "  [${loc}] ${spec} -- ${detail}" >&2
  done
  exit 1
fi

echo "PASS：${grand_total} 條 pathspec 全部命中 ≥1 檔"
exit 0
