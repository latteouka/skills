#!/usr/bin/env bash
# wave-close-guard.sh — wave-close 執行擋門（pre-push，main 側）
#
# 解決的問題：kit wave-close.sh 的觸發機制＝wave SKILL.md 收尾流程步驟 5 的
# 條文，靠收尾 session「記得呼叫」，無任何 hook。實證 2026-07-26：5 個已
# merge 波（axiom-fragment-fix／corpus-training／eng-guards／sso-cib／
# vector-lifecycle）dashboard 全數殘留 main、INDEX 全缺——wave-close 一次都
# 沒被呼叫；其 backlog 回寫閘門連帶失效（六波 11 筆 done 靠法醫重建）。
# 同母題第三次現形：frontmatter 歸檔沒人寫（0/52）→ 改 wave-close 當場呼叫
# → wave-close 自己也沒被呼叫。修法同族：把關掛在必經之路（push），不掛在
# 「要記得呼叫的工具」上。
#
# 判定規則（check）：
#   非 main branch／無 origin/main → 秒過。
#   從 origin/main..HEAD 的 merge commit subject 抽出 wave id
#   （worktree-wave-{id}／worktree-{id}／wave/{id}，PR merge subject 也含
#    branch 名故同樣可抽），對應 .claude/dev/wave-{id}.md 仍存在於 working
#   tree → BLOCK：該波已 merge 但 wave-close 沒跑（dashboard 該被清了）。
#   range 外的歷史殘留不攔（避免追溯擋無關 push）——存量清理走
#   worktree-merged-scan 提示＋人工補跑 wave-close。
#
# 逃生口：WAVE_CLOSE_SKIP="具體理由"（=1 不接受）——刻意保留 dashboard
# （如待人測清單尚未搬 inbox）時用，但注意 backlog-writeback-guard 仍會
# 獨立驗宣稱項的回寫。
#
# 全部用 ${var} 形式（macOS bash 3.2 + set -u 契約，同族 hook 一致）。
#
# [kit 參數化] 基底分支原硬編碼 main，改讀專案宣告 `.claude/kit/kit.yaml`
# 的 `base_branch`（預設 main）。wave id 抽取 pattern 原硬編碼
# worktree-|wave/，改讀宣告 `wave_branch_patterns`（空白分隔 glob，缺鍵 →
# 預設 "worktree-* wave/*"，逐位元組等價於原硬編碼；只有以 `*` 結尾的
# pattern 能算出前綴供 id 抽取，其餘 token 對本檔是 no-op）。宣告空值＝
# 關閉本擋門的 wave merge 判別（明示降級秒過）。其餘逐位元組保留。

set -u
set -o pipefail

kit_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
. "${kit_root}/lib/common.sh" 2>/dev/null || {
  echo "close-guard: 找不到 kit/lib/common.sh" >&2; exit 1; }

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
base_branch="$(kit_decl_get "${repo_root}/.claude/kit/kit.yaml" base_branch main)"
wave_branch_patterns="$(kit_decl_get "${repo_root}/.claude/kit/kit.yaml" wave_branch_patterns 'worktree-* wave/*')"

# wave id 抽取正則：只消費以 `*` 結尾的 pattern（前綴＋萬用字元＝可變 id 的
# glob 慣例），無 `*` 的 token 無法定義變動段落，跳過（不影響其餘 token）。
kit_wave_id_extract_regex() {
  local patterns="${1}" p prefix esc joined=""
  for p in ${patterns}; do
    case "${p}" in
      *'*') prefix="${p%\*}" ;;
      *) continue ;;
    esac
    [ -n "${prefix}" ] || continue
    esc="$(printf '%s' "${prefix}" | sed -e 's/[.[\^$()+{}|]/\\&/g')"
    if [ -z "${joined}" ]; then joined="${esc}[a-z0-9][a-z0-9-]*"
    else joined="${joined}|${esc}[a-z0-9][a-z0-9-]*"; fi
  done
  printf '%s' "${joined}"
}

# 對應的前綴去除 sed 表達式，逐行輸出供呼叫端組 -e 陣列。
kit_wave_id_strip_exprs() {
  local patterns="${1}" p prefix
  for p in ${patterns}; do
    case "${p}" in
      *'*') prefix="${p%\*}" ;;
      *) continue ;;
    esac
    [ -n "${prefix}" ] || continue
    printf 's|^%s||\n' "${prefix}"
  done
}

cmd="${1:-check}"

case "${cmd}" in

check)
  branch="$(git rev-parse --abbrev-ref HEAD)"
  if [ "${branch}" != "${base_branch}" ]; then
    exit 0
  fi
  if ! git rev-parse --verify -q "origin/${base_branch}" >/dev/null 2>&1; then
    exit 0
  fi

  if [ -z "${wave_branch_patterns}" ]; then
    echo "close-guard: PASS（wave_branch_patterns 宣告為空——wave merge 判別已停用，降級秒過）"
    exit 0
  fi

  id_extract_re="$(kit_wave_id_extract_regex "${wave_branch_patterns}")"
  if [ -z "${id_extract_re}" ]; then
    echo "close-guard: PASS（wave_branch_patterns 無可用前綴 pattern——判別已停用）"
    exit 0
  fi

  sed_args=()
  while IFS= read -r expr; do
    [ -n "${expr}" ] || continue
    sed_args+=(-e "${expr}")
  done < <(kit_wave_id_strip_exprs "${wave_branch_patterns}")

  ids="$(git log "origin/${base_branch}..HEAD" --merges --format='%s' 2>/dev/null \
    | grep -oE "${id_extract_re}" \
    | sed "${sed_args[@]}" | sort -u || true)"
  if [ -z "${ids}" ]; then
    echo "close-guard: PASS（push range 無 wave merge）"
    exit 0
  fi

  skip="${WAVE_CLOSE_SKIP:-}"
  if [ "${skip}" = "1" ]; then
    echo "close-guard: WAVE_CLOSE_SKIP=1 不接受——要具體理由不要開關。" >&2
    exit 1
  fi
  if [ -n "${skip}" ]; then
    echo "close-guard: SKIP（自報理由：${skip}）"
    exit 0
  fi

  stale=""
  for id in ${ids}; do
    # branch 名兩型：worktree-wave-{id}（原生 EnterWorktree）→ 去前綴後已含
    # wave-；worktree-{id}／wave/{id}（手動）→ 補 wave- 前綴。
    case "${id}" in
      wave-*) dash=".claude/dev/${id}.md" ;;
      *)      dash=".claude/dev/wave-${id}.md" ;;
    esac
    if [ -f "${dash}" ]; then
      stale="${stale}
  - ${dash}（wave merge 已在本次 push，wave-close 未跑）"
    fi
  done

  if [ -z "${stale}" ]; then
    echo "close-guard: PASS（push range 內 wave merge 的 dashboard 均已清除）"
    exit 0
  fi

  echo "close-guard: BLOCK——波已 merge 但 wave-close 沒跑：${stale}"
  echo ""
  echo "  wave-close 會：驗 backlog 回寫 → 摘要寫 wave-INDEX → git rm dashboard＋"
  echo "  ledger。不跑＝回寫閘門失效＋熱區只增不減（實證 64 檔超限）。"
  echo "  修法：bash ~/projects/skills/kit/scripts/wave-close.sh {id}（先 --dry-run），"
  echo "  刪除與 INDEX 一起 commit 後重 push。"
  echo '  刻意保留 dashboard：WAVE_CLOSE_SKIP="具體理由" git push ...'
  exit 1
  ;;

selftest)
  self="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
  tmp="$(mktemp -d)"
  trap 'rm -rf "${tmp}"' EXIT
  git -C "${tmp}" init -q
  gitc() { git -C "${tmp}" -c user.email=selftest@local -c user.name=selftest "$@"; }
  mkdir -p "${tmp}/.claude/dev"
  gitc commit --allow-empty -q -m init
  gitc branch -m main 2>/dev/null || true
  gitc update-ref refs/remotes/origin/main HEAD

  st_fail=0
  assert_rc() { # 期望rc 描述 [env 指令...]
    local want="${1}" desc="${2}" rc
    shift 2
    ( cd "${tmp}" && "$@" ) >/dev/null 2>&1
    rc=$?
    if [ "${rc}" -eq "${want}" ]; then
      echo "  ✓ ${desc}"
    else
      echo "  ✗ ${desc}（期望 exit ${want}，實得 ${rc}）"
      st_fail=1
    fi
  }

  echo "selftest（temp repo: ${tmp}）"

  assert_rc 0 "① 無 merge → 放行" bash "${self}" check

  gitc checkout -q -b worktree-wave-a
  echo "# wave a" > "${tmp}/.claude/dev/wave-a.md"
  gitc add -A; gitc commit -q -m "wave a 工作＋dashboard"
  gitc checkout -q main
  gitc merge -q --no-ff worktree-wave-a -m "Merge worktree-wave-a — selftest"
  assert_rc 1 "② wave merge＋dashboard 仍在 → 必攔" bash "${self}" check

  git -C "${tmp}" rm -q .claude/dev/wave-a.md
  gitc commit -q -m "wave-close 清理"
  assert_rc 0 "③ dashboard 已清（wave-close 已跑）→ 放行" bash "${self}" check

  gitc checkout -q -b hotfix-b
  gitc commit --allow-empty -q -m "hotfix"
  gitc checkout -q main
  gitc merge -q --no-ff hotfix-b -m "Merge branch 'hotfix-b'"
  assert_rc 0 "④ 非 wave merge（近似合法）→ 放行" bash "${self}" check

  gitc checkout -q -b worktree-wave-c
  mkdir -p "${tmp}/.claude/dev"   # 上一步 git rm 清空目錄時會連空目錄一併移除
  echo "# wave c" > "${tmp}/.claude/dev/wave-c.md"
  gitc add -A; gitc commit -q -m "wave c"
  gitc checkout -q main
  gitc merge -q --no-ff worktree-wave-c -m "Merge pull request #99 from org/worktree-wave-c"
  assert_rc 1 "⑤ PR 型 merge subject 也抽得出 id → 必攔" bash "${self}" check
  assert_rc 0 "⑥ 逃生口帶理由 → 放行" env WAVE_CLOSE_SKIP="selftest 理由" bash "${self}" check
  assert_rc 1 "⑦ 逃生口 =1 → 拒絕" env WAVE_CLOSE_SKIP=1 bash "${self}" check

  gitc update-ref refs/remotes/origin/main HEAD
  assert_rc 0 "⑧ range 外歷史殘留 dashboard → 不追溯攔" bash "${self}" check

  gitc checkout -q -b worktree-wave-d
  assert_rc 0 "⑨ 非 main branch → 直接放行" bash "${self}" check

  if [ "${st_fail}" -eq 0 ]; then
    echo "selftest: PASS（9/9）"
    exit 0
  fi
  echo "selftest: FAIL"
  exit 1
  ;;

*)
  echo "用法: wave-close-guard.sh {check|selftest}"
  exit 2
  ;;
esac
