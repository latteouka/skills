#!/usr/bin/env bash
# wave-regate-guard.sh — merge re-gate 唯一入口擋門（merge train 的「唯一入口」性質）
#
# 解決的問題：合併協助 step 4 條文寫「merge re-gate 強制」，但條文≠執行
# （實證 d7079dc9b：workbench-integrity merge 帶 exhibit-return typecheck 紅燈
# 上 main，pre-push 未攔，下游多個波收尾撞既存紅、逐一人工歸因）。本檔把
# 條文機器化：wave-gate 在 main 上收尾 PASS 時寫戳記，pre-push 驗「push 的
# main 若含 wave merge commit，戳記之後不得再出現新的 wave merge」。
#
# 子指令：
#   stamp     （wave-gate main PASS 時自動呼叫）寫 HEAD hash 到 git-common-dir
#   preauth   （wave-gate branch 收尾 PASS 時自動呼叫）記「已驗證的合體樹」
#             tree hash——branch gate 因 freshness 強制 HEAD..main=0，驗的
#             已是 merge 後會出現的那棵樹；merge --no-ff 未帶新內容時樹
#             位元組級相同，check 據此免除重複的 merge re-gate（單次有效）。
#   check     （pre-push 呼叫）驗證。非 main branch／無 wave merge → 秒過，
#             不影響「docs-only push 秒級完成」的設計。
#   status    印戳記＋preauth 狀態。恆 exit 0。
#   selftest  隔離自測（temp repo）：雙向驗證——違規必攔、近似合法必放。
#
# 判定規則（check）：
#   range = origin/main..HEAD 的 merge commit，subject 匹配 worktree-|wave/
#   （pull merge「Merge remote-tracking branch...」與 hotfix merge 不匹配→不攔；
#    全庫誤報驗證見 selftest ⑤——非 wave merge 必放行）
#   零匹配 → PASS。有匹配 → 戳記存在、是 HEAD 祖先、且戳記..HEAD 無新 wave
#   merge 才 PASS——允許 re-gate 後的 wave-close 清理 commit（非 merge），
#   但任何「re-gate 之後又 merge 進來的波」必須重新 re-gate。
#
# 逃生口：WAVE_REGATE_SKIP="具體理由"（=1 不接受——要理由不要開關，
# 比照 wave-close 的 --skip-backlog-check 語意）。
#
# 鎖／戳記位置：$(git rev-parse --git-common-dir)/wave-regate-pass
#   跨 worktree 共享、不髒 git status、不進版控（同 wave-closure-lock 選址）。
#
# 全部用 ${var} 形式（macOS bash 3.2 + set -u 契約，同族 hook 一致）。
#
# [kit 參數化] 基底分支原硬編碼 main，改讀專案宣告 `.claude/kit/kit.yaml`
# 的 `base_branch`（缺檔／缺 key → 預設 main，行為與 dfaa 原版完全一致）。
# wave merge 的 branch pattern（worktree-|wave/）是 kit 自身命名慣例，
# 刻意不參數化。

set -u
set -o pipefail

kit_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
. "${kit_root}/lib/common.sh" 2>/dev/null || {
  echo "regate-guard: 找不到 kit/lib/common.sh" >&2; exit 1; }

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
base_branch="$(kit_decl_get "${repo_root}/.claude/kit/kit.yaml" base_branch main)"

cmd="${1:-check}"

wave_merge_pattern='worktree-|wave/'

stamp_path() {
  local common
  common="$(cd "$(git rev-parse --git-common-dir)" && pwd)" || return 1
  printf '%s/wave-regate-pass' "${common}"
}

# 預授權檔：branch 收尾 gate 於「已含 main 的合體樹」上 PASS 時寫入
# （wave-gate 收口自動呼叫 preauth）。格式兩行：tree hash＋來源 commit。
# check 消費規則見 check 段——樹相等＝機器驗證的等價條件，main 在 gate
# 之後又前進過則 merge 樹必不同，自動退回完整 re-gate，無誤放窗口。
preauth_path() {
  local common
  common="$(cd "$(git rev-parse --git-common-dir)" && pwd)" || return 1
  printf '%s/wave-regate-preauth' "${common}"
}

case "${cmd}" in

stamp)
  sp="$(stamp_path)" || exit 1
  git rev-parse HEAD > "${sp}"
  echo "regate-guard: STAMPED（$(git rev-parse --short HEAD)）"
  exit 0
  ;;

preauth)
  # 由 wave-gate 於 branch 收尾 PASS 時呼叫。防呆不信任呼叫端：
  # HEAD 必須已含 main（合體樹）——否則 gate 驗的不是 merge 後會出現的樹，
  # 預授權無意義，拒寫（不報錯，印原因）。
  if git rev-parse --verify -q "${base_branch}" >/dev/null 2>&1 \
     && ! git merge-base --is-ancestor "${base_branch}" HEAD 2>/dev/null; then
    echo "regate-guard: preauth 未寫——HEAD 未含 ${base_branch}（先 git merge ${base_branch} 再跑收尾 gate）"
    exit 0
  fi
  pp="$(preauth_path)" || exit 1
  {
    git rev-parse 'HEAD^{tree}'
    git rev-parse HEAD
  } > "${pp}"
  echo "regate-guard: PREAUTH（tree $(git rev-parse --short 'HEAD^{tree}') @ $(git rev-parse --short HEAD)）"
  echo "  merge --no-ff 後 push：merge 樹與此樹相同即免重跑 merge re-gate（單次有效）。"
  echo "  ${base_branch} 若在此之後又前進，merge 樹必不同 → 照舊要求完整 re-gate。"
  exit 0
  ;;

status)
  sp="$(stamp_path)" || exit 0
  if [ -f "${sp}" ]; then
    echo "regate-guard: stamp=$(cut -c1-9 "${sp}")"
  else
    echo "regate-guard: 無戳記"
  fi
  pp="$(preauth_path)" || exit 0
  if [ -f "${pp}" ]; then
    echo "regate-guard: preauth tree=$(head -1 "${pp}" | cut -c1-9)"
  fi
  exit 0
  ;;

check)
  branch="$(git rev-parse --abbrev-ref HEAD)"
  if [ "${branch}" != "${base_branch}" ]; then
    exit 0
  fi
  if ! git rev-parse --verify -q "origin/${base_branch}" >/dev/null 2>&1; then
    exit 0
  fi

  wave_merges="$(git log "origin/${base_branch}..HEAD" --merges --format='%h %s' 2>/dev/null \
    | grep -E "${wave_merge_pattern}" || true)"
  if [ -z "${wave_merges}" ]; then
    echo "regate-guard: PASS（push range 無 wave merge）"
    exit 0
  fi

  skip="${WAVE_REGATE_SKIP:-}"
  if [ "${skip}" = "1" ]; then
    echo "regate-guard: WAVE_REGATE_SKIP=1 不接受——要具體理由不要開關。" >&2
    echo '  用法: WAVE_REGATE_SKIP="main 上 hotfix 已親跑 typecheck+test" git push ...' >&2
    exit 1
  fi
  if [ -n "${skip}" ]; then
    echo "regate-guard: SKIP（自報理由：${skip}）"
    exit 0
  fi

  offending="${wave_merges}"
  sp="$(stamp_path)" || sp=""
  if [ -n "${sp}" ] && [ -f "${sp}" ]; then
    stamp_hash="$(cat "${sp}")"
    if git rev-parse --verify -q "${stamp_hash}" >/dev/null 2>&1 \
       && git merge-base --is-ancestor "${stamp_hash}" HEAD 2>/dev/null; then
      offending="$(git log "${stamp_hash}..HEAD" --merges --format='%h %s' 2>/dev/null \
        | grep -E "${wave_merge_pattern}" || true)"
    fi
  fi

  if [ -z "${offending}" ]; then
    echo "regate-guard: PASS（wave merge 已經 re-gate 戳記覆蓋）"
    exit 0
  fi

  # 預授權路徑：branch 收尾 gate 已在「含 main 的合體樹」上 PASS（wave-gate
  # freshness 強制 HEAD..main=0）→ merge --no-ff 若沒帶進任何新內容，merge
  # commit 的 tree 與 gate 驗過的 tree 位元組級相同。全部未蓋戳 wave merge
  # 的樹都命中 preauth tree 才放行（自動補戳＋銷毀 preauth，單次有效）；
  # 任一不同（main 期間前進／別波混入）→ 照舊 BLOCK 要求完整 re-gate。
  pp="$(preauth_path)" || pp=""
  if [ -n "${pp}" ] && [ -f "${pp}" ]; then
    preauth_tree="$(head -1 "${pp}")"
    uncovered=""
    while IFS= read -r line; do
      [ -z "${line}" ] && continue
      mh="${line%% *}"
      mtree="$(git rev-parse "${mh}^{tree}" 2>/dev/null || echo bad)"
      if [ "${mtree}" != "${preauth_tree}" ]; then
        uncovered="${uncovered}${line}
"
      fi
    done <<EOF
${offending}
EOF
    if [ -z "${uncovered}" ]; then
      git rev-parse HEAD > "$(stamp_path)"
      rm -f "${pp}"
      echo "regate-guard: PASS（preauth 樹相符——branch 收尾 gate 已於合體樹 PASS，merge 未帶進新內容）"
      echo "  已自動補戳（$(git rev-parse --short HEAD)）並銷毀 preauth（單次有效）。"
      # 收尾鎖收口：舊流程由 main 側 re-gate PASS 時 conditional-release；
      # preauth 路徑跳過 main gate，等價收口點在此——不放鎖下一波 acquire 會卡死。
      lock_sh="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/wave-closure-lock.sh"
      if [ -f "${lock_sh}" ]; then
        bash "${lock_sh}" conditional-release || true
      fi
      exit 0
    fi
    echo "regate-guard: preauth 存在但樹不符（${base_branch} 在 gate 之後前進過？）——退回完整 re-gate。"
  fi

  echo "regate-guard: BLOCK——以下 wave merge 未經 merge re-gate："
  printf '%s\n' "${offending}" | sed 's/^/  /'
  echo "  修法：在 ${base_branch} 上跑 bash ~/projects/skills/kit/engines/wave-gate.sh 收尾（merge re-gate）——"
  echo "  PASS 時自動寫戳記並釋放收尾鎖，之後 push 即放行。"
  echo '  確定不適用（極少數）：WAVE_REGATE_SKIP="具體理由" git push ...'
  exit 1
  ;;

selftest)
  self="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
  tmp="$(mktemp -d)"
  trap 'rm -rf "${tmp}"' EXIT
  git -C "${tmp}" init -q
  gitc() { git -C "${tmp}" -c user.email=selftest@local -c user.name=selftest "$@"; }
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

  assert_rc 0 "① 乾淨 main（無 merge）→ 放行" bash "${self}" check

  gitc checkout -q -b worktree-wave-x
  gitc commit --allow-empty -q -m "wave x work"
  gitc checkout -q main
  gitc merge -q --no-ff worktree-wave-x -m "Merge worktree-wave-x — selftest"
  assert_rc 1 "② wave merge 無戳記 → 必攔（違規命中）" bash "${self}" check

  assert_rc 0 "③ stamp 寫入成功" bash "${self}" stamp
  assert_rc 0 "④ 戳記覆蓋後 → 放行" bash "${self}" check

  gitc commit --allow-empty -q -m "docs: wave-close 清理（非 merge）"
  assert_rc 0 "⑤ 戳記後的非 merge commit（wave-close 清理）→ 放行" bash "${self}" check

  gitc checkout -q -b worktree-wave-y
  gitc commit --allow-empty -q -m "wave y work"
  gitc checkout -q main
  gitc merge -q --no-ff worktree-wave-y -m "Merge worktree-wave-y — selftest"
  assert_rc 1 "⑥ 戳記之後的新 wave merge → 必攔" bash "${self}" check

  assert_rc 0 "⑦ 逃生口帶理由 → 放行" env WAVE_REGATE_SKIP="selftest 理由" bash "${self}" check
  assert_rc 1 "⑧ 逃生口 =1 無理由 → 拒絕" env WAVE_REGATE_SKIP=1 bash "${self}" check

  bash -c "cd '${tmp}' && bash '${self}' stamp" >/dev/null 2>&1
  gitc checkout -q -b hotfix-z
  gitc commit --allow-empty -q -m "hotfix work"
  gitc checkout -q main
  gitc merge -q --no-ff hotfix-z -m "Merge branch 'hotfix-z'"
  assert_rc 0 "⑨ 非 wave merge（hotfix，近似合法）→ 放行" bash "${self}" check

  gitc checkout -q -b worktree-wave-z
  assert_rc 0 "⑩ 非 main branch → 直接放行" bash "${self}" check

  # ⑪⑫ preauth 路徑——空 commit 樹全同無法判別，改用真檔案內容
  gitc checkout -q main
  gitc checkout -q -b worktree-wave-p
  echo "p-content" > "${tmp}/p.txt"
  gitc add p.txt && gitc commit -q -m "wave p work"
  assert_rc 0 "⑪a branch 已含 main → preauth 寫入" bash "${self}" preauth
  gitc checkout -q main
  gitc merge -q --no-ff worktree-wave-p -m "Merge worktree-wave-p — selftest"
  assert_rc 0 "⑪b preauth 樹相符（先合後驗）→ 免 re-gate 放行" bash "${self}" check
  assert_rc 0 "⑪c 自動補戳後再 check → 照樣放行（preauth 已銷毀）" bash "${self}" check

  gitc checkout -q -b worktree-wave-q
  echo "q-content" > "${tmp}/q.txt"
  gitc add q.txt && gitc commit -q -m "wave q work"
  bash -c "cd '${tmp}' && bash '${self}' preauth" >/dev/null 2>&1
  gitc checkout -q main
  echo "m-moved" > "${tmp}/m.txt"
  gitc add m.txt && gitc commit -q -m "main moved after preauth"
  gitc merge -q --no-ff worktree-wave-q -m "Merge worktree-wave-q — selftest"
  assert_rc 1 "⑫ preauth 後 main 前進 → 樹不符 → 必攔（退回完整 re-gate）" bash "${self}" check

  # ⑬ preauth 防呆：wave-z 分岔於舊 main（其後 main 已前進）→ HEAD 未含
  # main → 拒寫（exit 0 但不留檔）。⑫ 已把 preauth 消耗殆盡，殘檔＝⑬ 誤寫。
  gitc checkout -q worktree-wave-z
  preauth_file="${tmp}/.git/wave-regate-preauth"
  rm -f "${preauth_file}"
  assert_rc 0 "⑬a preauth 於未含 main 的 branch → exit 0 不報錯" bash "${self}" preauth
  if [ ! -f "${preauth_file}" ]; then
    echo "  ✓ ⑬b 防呆生效——preauth 檔未寫入"
  else
    echo "  ✗ ⑬b 防呆失效——HEAD 未含 main 仍寫了 preauth"
    st_fail=1
  fi

  if [ "${st_fail}" -eq 0 ]; then
    echo "selftest: PASS（15/15）"
    exit 0
  fi
  echo "selftest: FAIL"
  exit 1
  ;;

*)
  echo "用法: wave-regate-guard.sh {stamp|check|status|selftest}"
  exit 2
  ;;
esac
