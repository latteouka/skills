#!/usr/bin/env bash
# backlog-writeback-guard.sh — backlog 回寫擋門（pre-push，main 側）
#
# 解決的問題：backlog 回寫閘門原本只掛在 kit wave-close.sh 內——但六波實證
# （2026-07-26 法醫重建：eng-guards／audit-metrics／workbench-integrity／
# authz／group-summary／vector-lifecycle 對 backlog 改動全為 0，11 筆 done
# 靠事後 git 反查補上 565ff0fb4）：各波清 worktree 走原生 ExitWorktree／
# 手動清理而非 wave-close → 閘門永不觸發。與 frontmatter 歸檔、B-113 同構
# 的母題：把關掛在「要記得呼叫的工具」上＝沒把關。本檔把檢查前移到 push
# 這個必經之路。
#
# 判定規則（check，與 kit wave-close.sh 的 backlog 閘門同判準——dashboard
# 同一行同時出現 B-NNN 與 ✅ ＝宣稱完成；改判準時兩處同步改）：
#   非 main branch／無 origin/main → 秒過。
#   changed = origin/main..HEAD 內有改動的 .claude/dev/wave-*.md
#             （排除 wave-INDEX.md 與 *-ledger.md——INDEX 摘要欄與 ledger
#              敘事都會出現 B-NNN＋✅ 字面，但不是完成宣稱）
#   只掃 range 內觸碰的 dashboard：進行中他波的 dashboard 也在 main 上，
#   全量掃會把人家波中途的 ✅ 當違規（誤報）；merge 誰的波就查誰。
#   被刪除的 dashboard（wave-close 清理後 push）→ 跳過——刪除發生在
#   wave-close 之後，該波已被 wave-close 自己的閘門驗過。
#   宣稱 ✅ 的 B-NNN 在 backlog 仍為 ready → BLOCK。
#
# 逃生口：BACKLOG_SYNC_SKIP="具體理由"（=1 不接受，比照 WAVE_REGATE_SKIP）。
#
# 全部用 ${var} 形式（macOS bash 3.2 + set -u 契約，同族 hook 一致）。
#
# [kit 參數化] 基底分支原硬編碼 main，改讀專案宣告 `.claude/kit/kit.yaml`
# 的 `base_branch`（預設 main）。其餘逐位元組保留。

set -u
set -o pipefail

kit_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
. "${kit_root}/lib/common.sh" 2>/dev/null || {
  echo "backlog-guard: 找不到 kit/lib/common.sh" >&2; exit 1; }

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
base_branch="$(kit_decl_get "${repo_root}/.claude/kit/kit.yaml" base_branch main)"

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

  changed="$(git diff --name-only "origin/${base_branch}..HEAD" -- ':(top).claude/dev/wave-*.md' 2>/dev/null \
    | grep -v 'wave-INDEX\.md' | grep -v -- '-ledger\.md' || true)"
  if [ -z "${changed}" ]; then
    echo "backlog-guard: PASS（push range 無 dashboard 改動）"
    exit 0
  fi

  skip="${BACKLOG_SYNC_SKIP:-}"
  if [ "${skip}" = "1" ]; then
    echo "backlog-guard: BACKLOG_SYNC_SKIP=1 不接受——要具體理由不要開關。" >&2
    exit 1
  fi
  if [ -n "${skip}" ]; then
    echo "backlog-guard: SKIP（自報理由：${skip}）"
    exit 0
  fi

  backlog_dir=".claude/dev/backlog"
  backlog_md=".claude/dev/backlog.md"
  if [ ! -d "${backlog_dir}" ] && [ ! -f "${backlog_md}" ]; then
    echo "backlog-guard: PASS（無 backlog）"
    exit 0
  fi

  stale=""
  inspected=0
  while IFS= read -r dash; do
    [ -n "${dash}" ] || continue
    [ -f "${dash}" ] || continue
    inspected=$((inspected + 1))
    claimed="$(grep '✅' "${dash}" 2>/dev/null | grep -oE 'B-[0-9]{3}' | sort -u || true)"
    for bid in ${claimed}; do
      st=""
      if [ -d "${backlog_dir}" ]; then
        bf="${backlog_dir}/${bid}.md"
        [ -f "${bf}" ] || continue
        st="$(LC_ALL=C grep -am1 '^status:' "${bf}" 2>/dev/null | LC_ALL=C sed 's/^status: *"*//;s/"*$//' || true)"
      elif [ -f "${backlog_md}" ]; then
        line="$(grep -m1 "^| ${bid} |" "${backlog_md}" 2>/dev/null || true)"
        [ -n "${line}" ] || continue
        st="$(printf '%s' "${line}" | awk -F'|' '{gsub(/^ +| +$/,"",$7); print $7}')"
      fi
      case "${st}" in
        ready|ready*) stale="${stale}
  - ${bid}（${dash} 宣稱 ✅，backlog 仍 ready）" ;;
      esac
    done
  done <<EOF
${changed}
EOF

  if [ -z "${stale}" ]; then
    echo "backlog-guard: PASS（inspected:${inspected} dashboard，宣稱項均已回寫）"
    exit 0
  fi

  echo "backlog-guard: BLOCK——dashboard 宣稱完成但 backlog 未回寫：${stale}"
  echo ""
  echo "  backlog 是 /wave batch 的唯一取料來源，漏回寫的項會重新排波做第二次。"
  echo "  修法：把上列條目 status 改為 done:{wave-id}（明細補 proof：commit hash／"
  echo "  實測輸出），commit 後重 push。根因未修用 🔶止血:{wave-id}，不標 done。"
  echo '  確定不適用：BACKLOG_SYNC_SKIP="具體理由" git push ...'
  exit 1
  ;;

selftest)
  self="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
  tmp="$(mktemp -d)"
  trap 'rm -rf "${tmp}"' EXIT
  git -C "${tmp}" init -q
  gitc() { git -C "${tmp}" -c user.email=selftest@local -c user.name=selftest "$@"; }
  mkdir -p "${tmp}/.claude/dev/backlog"
  cat > "${tmp}/.claude/dev/backlog/B-001.md" <<'FIX'
---
id: B-001
type: BUG
pri: P1
flow: direct
status: "ready"
matrix: "x.yaml"
created: 2026-07-29
---
FIX
  cat > "${tmp}/.claude/dev/backlog/B-002.md" <<'FIX'
---
id: B-002
type: BUG
pri: P1
flow: direct
status: "ready"
matrix: "x.yaml"
created: 2026-07-29
---
FIX
  cat > "${tmp}/.claude/dev/backlog/B-003.md" <<'FIX'
---
id: B-003
type: BUG
pri: P1
flow: direct
status: "done:wave-x"
matrix: "x.yaml"
created: 2026-07-29
---
## proof
test
FIX
  gitc add -A; gitc commit -q -m init
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

  assert_rc 0 "① range 無 dashboard 改動 → 放行" bash "${self}" check

  # 在 main 上帶進一份宣稱 ✅ B-001 的 dashboard（模擬 wave merge）
  cat > "${tmp}/.claude/dev/wave-a.md" <<'FIX'
# wave a
| 🤖-1 | B-001 修好了 | ✅ |
| 🤖-2 | 非目標：不做 B-002 |
FIX
  gitc add -A; gitc commit -q -m "merge wave a"
  assert_rc 1 "② 宣稱 ✅ B-001 但 backlog ready → 必攔" bash "${self}" check

  sed -i '' 's/status: "ready"/status: "done:wave-a"/' "${tmp}/.claude/dev/backlog/B-001.md"
  gitc add -A; gitc commit -q -m "backlog 回寫"
  assert_rc 0 "③ 回寫 done 後 → 放行" bash "${self}" check
  assert_rc 0 "④ B-002 只被提及無 ✅（近似合法）→ 放行" bash "${self}" check

  cat > "${tmp}/.claude/dev/wave-b.md" <<'FIX'
# wave b
| 🤖-1 | B-999 不在 backlog | ✅ |
| 🤖-2 | B-003 已 done | ✅ |
FIX
  gitc add -A; gitc commit -q -m "merge wave b"
  assert_rc 0 "⑤ 宣稱項不在 backlog／已 done → 放行" bash "${self}" check

  cat > "${tmp}/.claude/dev/wave-c.md" <<'FIX'
| 🤖-1 | B-002 也修了 | ✅ |
FIX
  gitc add -A; gitc commit -q -m "merge wave c"
  assert_rc 1 "⑥ 新 dashboard 宣稱 B-002 仍 ready → 必攔" bash "${self}" check
  assert_rc 0 "⑦ 逃生口帶理由 → 放行" env BACKLOG_SYNC_SKIP="selftest 理由" bash "${self}" check
  assert_rc 1 "⑧ 逃生口 =1 → 拒絕" env BACKLOG_SYNC_SKIP=1 bash "${self}" check

  # range 收斂（origin/main 推進）後，wave-c 的違規不再屬於本次 push → in-flight 不誤傷
  gitc update-ref refs/remotes/origin/main HEAD
  assert_rc 0 "⑨ range 外的既存宣稱（in-flight 他波）→ 不誤傷" bash "${self}" check

  git -C "${tmp}" rm -q .claude/dev/wave-c.md
  gitc commit -q -m "wave-close 清理"
  assert_rc 0 "⑩ 被刪除的 dashboard → 跳過" bash "${self}" check

  gitc checkout -q -b worktree-wave-z
  assert_rc 0 "⑪ 非 main branch → 直接放行" bash "${self}" check

  if [ "${st_fail}" -eq 0 ]; then
    echo "selftest: PASS（11/11）"
    exit 0
  fi
  echo "selftest: FAIL"
  exit 1
  ;;

*)
  echo "用法: backlog-writeback-guard.sh {check|selftest}"
  exit 2
  ;;
esac
