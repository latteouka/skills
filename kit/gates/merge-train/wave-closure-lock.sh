#!/usr/bin/env bash
# wave-closure-lock.sh — 收尾互斥鎖（跨 worktree 全域）
#
# 解決的問題：多波並行時，收尾 gate（10-20 分鐘）與 merge 之間 main 被他波
# 推進 → 本輪 gate 證據 stale → 全套重跑。實證：2026-07-26 wave
# gate-governance 收尾重跑 9 輪（/tmp/dfaa-gate-governance-final1..9.log），
# 多輪純因並行波推進 main 報廢。
#
# 臨界區 = [收尾 gate 開跑 … merge 進 main 後的 merge re-gate PASS]。
# 由 wave-gate.sh 自動呼叫：
#   - branch 收尾 phase 開頭 acquire（同 branch 重入，不自我阻塞）
#   - main 上收尾（= merge re-gate）不取鎖，PASS 時 release --force 收口
#
# 鎖位置：$(git rev-parse --git-common-dir)/wave-closure.lock/
#   - 目錄鎖（mkdir 原子性，macOS bash 3.2 可用）
#   - git-common-dir 跨所有 worktree 共享 → 天然全域互斥
#   - 不在 working tree → 不髒 git status、不進版控
#
# 子指令：
#   acquire   取鎖。他波持有 → 每 30 秒印等待訊息（等待屬正常，勿中斷），
#             上限 45 分鐘後 exit 1。同 branch 重入直接成功。
#             🤖-3 camp 看門：持鎖 >90 分鐘且 main 無 merge commit → 警告。
#   release   放鎖。非持有 branch 拒絕（exit 1）；--force 強制清
#             （殘鎖、棄波、main 收口用）。無鎖時安靜成功。
#   conditional-release  🤖-2 條件式放鎖（wave-gate.sh main re-gate 收口呼叫）：
#             僅當鎖持有者 branch tip 已在 HEAD 祖先鏈上才釋放；否則不動鎖。
#             恆 exit 0（放或不放都是正確的政策決策）。
#   status    印 FREE / HELD by 誰、持有多久。恆 exit 0。
#   selftest  隔離自測（temp git repo）：互斥、重入、釋放權限、釋放後可取得、
#             條件式放鎖、camp 看門。
#
# 環境變數（selftest / 特殊場景用）：
#   WAVE_LOCK_WAIT_SECONDS  等待上限（預設 2700 = 45 分鐘）
#   WAVE_LOCK_POLL_SECONDS  輪詢間隔（預設 30）
#   WAVE_LOCK_CAMP_SECONDS  camp 看門閾值（預設 5400 = 90 分鐘）
#
# 全部用 ${var} 形式（macOS bash 3.2 + set -u 裸 $var 接全形標點會誤判
# unbound variable，見 dev-ref claude-code--hooks-quality-gates）。
#
# [kit 參數化] camp 看門的基底分支原硬編碼 main，改讀專案宣告
# `.claude/kit/kit.yaml` 的 `base_branch`（預設 main）；錯誤訊息內
# 自身路徑改指 kit 位置。其餘逐位元組保留。

set -u -o pipefail

cmd="${1:-status}"
if [ "$#" -gt 0 ]; then shift; fi

kit_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
. "${kit_root}/lib/common.sh" 2>/dev/null || {
  echo "closure-lock: 找不到 kit/lib/common.sh" >&2; exit 1; }

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
base_branch="$(kit_decl_get "${repo_root}/.claude/kit/kit.yaml" base_branch main)"

common_dir="$(cd "$(git rev-parse --git-common-dir)" && pwd)" || exit 1
lock_dir="${common_dir}/wave-closure.lock"
info_file="${lock_dir}/info"
branch="$(git rev-parse --abbrev-ref HEAD)"

wait_seconds="${WAVE_LOCK_WAIT_SECONDS:-2700}"
poll_seconds="${WAVE_LOCK_POLL_SECONDS:-30}"
stale_warn_seconds=21600  # 6 小時——超過視為疑似殘鎖，只警告不自動清
camp_warn_seconds="${WAVE_LOCK_CAMP_SECONDS:-5400}"  # 90 分鐘——持鎖未 merge 警告

now_epoch() { date +%s; }

read_info_field() {
  [ -f "${info_file}" ] || return 1
  awk -F'=' -v k="${1}" '$1==k {print substr($0, length(k)+2); exit}' "${info_file}"
}

holder_desc() {
  local hb ht hp age
  hb="$(read_info_field branch || true)"
  ht="$(read_info_field epoch || true)"
  hp="$(read_info_field pid || true)"
  age=$(( ($(now_epoch) - ${ht:-0}) / 60 ))
  echo "${hb:-?}（已持有 ${age} 分鐘，pid ${hp:-?}）"
}

write_info() {
  printf 'branch=%s\npid=%s\nepoch=%s\ntime=%s\n' \
    "${branch}" "$$" "$(now_epoch)" "$(date '+%Y-%m-%d %H:%M:%S')" > "${info_file}"
}

case "${cmd}" in

acquire)
  deadline=$(( $(now_epoch) + wait_seconds ))
  while true; do
    if mkdir "${lock_dir}" 2>/dev/null; then
      write_info
      echo "closure-lock: ACQUIRED（branch=${branch}）"
      exit 0
    fi
    holder_branch="$(read_info_field branch || true)"
    if [ "${holder_branch:-}" = "${branch}" ]; then
      write_info
      echo "closure-lock: RE-ENTER（同 branch 重入，branch=${branch}）"
      exit 0
    fi
    holder_epoch="$(read_info_field epoch || true)"
    if [ -n "${holder_epoch:-}" ]; then
      lock_age=$(( $(now_epoch) - holder_epoch ))
      if [ "${lock_age}" -gt "${stale_warn_seconds}" ]; then
        echo "closure-lock: ⚠️ 鎖已持有超過 6 小時，疑似殘鎖（波被棄置？）——"
        echo "  確認持有波已死後手動清：bash ~/projects/skills/kit/gates/merge-train/wave-closure-lock.sh release --force"
      elif [ "${lock_age}" -gt "${camp_warn_seconds}" ]; then
        holder_tip="$(git rev-parse --verify -q "${holder_branch}" 2>/dev/null || true)"
        holder_merged=0
        if [ -n "${holder_tip:-}" ] && git merge-base --is-ancestor "${holder_tip}" "${base_branch}" 2>/dev/null; then
          holder_merged=1
        fi
        if [ "${holder_merged}" -eq 0 ]; then
          echo "closure-lock: ⚠️ 疑似 camp——${holder_branch:-?} 持鎖 $(( lock_age / 60 )) 分鐘且尚未 merge 進 ${base_branch}。"
          echo "  查證持有波進度：git log --oneline ${holder_branch:-?} | head -5"
        fi
      fi
    fi
    if [ "$(now_epoch)" -ge "${deadline}" ]; then
      echo "closure-lock: TIMEOUT——等待 $(( wait_seconds / 60 )) 分鐘仍被 $(holder_desc) 持有。"
      echo "  他波收尾可能卡住；確認後手動清：bash ~/projects/skills/kit/gates/merge-train/wave-closure-lock.sh release --force"
      exit 1
    fi
    remain=$(( (deadline - $(now_epoch)) / 60 ))
    echo "closure-lock: WAITING——被 $(holder_desc) 持有；等待屬正常，勿中斷（剩餘上限 ${remain} 分鐘）"
    echo "  （鎖只互斥「波收尾臨界區」——docs commit／push 不受鎖約束，不用等鎖。"
    echo "   持鎖波的 freshness 會吸收 docs commit。實證 2026-07-26：docs session"
    echo "   自願等鎖 × 持鎖波等其 commit ＝ 互等死結）"
    echo "  （持鎖 process 已結束屬正常——gate PASS 後鎖保留至 merge，不隨 process 存活，"
    echo "   勿據此 release --force；真殘鎖判準＝stale_warn_seconds（$(( stale_warn_seconds / 3600 )) 小時，"
    echo "   超過時上方會出現疑似殘鎖警告））"
    sleep "${poll_seconds}"
  done
  ;;

release)
  force=0
  if [ "${1:-}" = "--force" ]; then force=1; fi
  if [ ! -d "${lock_dir}" ]; then
    echo "closure-lock: FREE（無鎖可釋放）"
    exit 0
  fi
  holder_branch="$(read_info_field branch || true)"
  if [ "${force}" -eq 1 ] || [ "${holder_branch:-}" = "${branch}" ]; then
    desc="$(holder_desc)"
    rm -rf "${lock_dir}"
    echo "closure-lock: RELEASED（原持有者 ${desc}）"
    exit 0
  fi
  echo "closure-lock: REFUSED——鎖屬 ${holder_branch:-?}，非本 branch（${branch}）。"
  echo "  確定要清用：bash ~/projects/skills/kit/gates/merge-train/wave-closure-lock.sh release --force"
  exit 1
  ;;

conditional-release)
  if [ ! -d "${lock_dir}" ]; then
    echo "closure-lock: FREE（無鎖可釋放）"
    exit 0
  fi
  holder_branch="$(read_info_field branch || true)"
  if [ -z "${holder_branch:-}" ]; then
    echo "closure-lock: 無法讀取持有者資訊，鎖保持不動（手動清：release --force）。"
    exit 0
  fi
  holder_tip="$(git rev-parse --verify -q "${holder_branch}" 2>/dev/null || true)"
  if [ -z "${holder_tip:-}" ]; then
    echo "closure-lock: 持有 branch（${holder_branch}）已不存在，鎖保持不動（手動清：release --force）。"
    exit 0
  fi
  if git merge-base --is-ancestor "${holder_tip}" HEAD 2>/dev/null; then
    desc="$(holder_desc)"
    rm -rf "${lock_dir}"
    echo "closure-lock: RELEASED（持有波 ${holder_branch} 已 merge，${desc}）"
  else
    echo "closure-lock: 鎖持有者（${holder_branch}）尚未 merge 進 HEAD，鎖保持不動。"
    echo "  本次 re-gate PASS 但不釋放鎖——鎖屬另一波的收尾臨界區。"
  fi
  exit 0
  ;;

status)
  if [ -d "${lock_dir}" ]; then
    echo "closure-lock: HELD by $(holder_desc)"
    echo "  （鎖只互斥「波收尾臨界區」（gate→merge→re-gate）——docs commit／push"
    echo "   不受鎖約束，不用等鎖；只有要收尾的波才需要等）"
    echo "  （持鎖 process 已結束屬正常——gate PASS 後鎖保留至 merge，不隨 process 存活，"
    echo "   勿據此 release --force；真殘鎖判準＝stale_warn_seconds（$(( stale_warn_seconds / 3600 )) 小時，"
    echo "   超過時 acquire 等待方會見疑似殘鎖警告））"
  else
    echo "closure-lock: FREE"
  fi
  exit 0
  ;;

selftest)
  # 隔離自測：在 temp git repo 內跑，不碰真實 repo 的鎖。
  self="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
  tmp="$(mktemp -d)"
  trap 'rm -rf "${tmp}"' EXIT
  git -C "${tmp}" init -q
  git -C "${tmp}" -c user.email=selftest@local -c user.name=selftest \
    commit --allow-empty -q -m init
  db="$(git -C "${tmp}" rev-parse --abbrev-ref HEAD)"

  st_fail=0
  assert_rc() { # 期望rc 描述 指令...
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

  echo "selftest（temp repo: ${tmp}，default branch: ${db}）"
  assert_rc 0 "① acquire 取得空鎖" bash "${self}" acquire
  [ -d "${tmp}/.git/wave-closure.lock" ] \
    && echo "  ✓ ② 鎖目錄存在於 git-common-dir" \
    || { echo "  ✗ ② 鎖目錄不存在"; st_fail=1; }
  assert_rc 0 "③ 同 branch 重入不自我阻塞" bash "${self}" acquire
  git -C "${tmp}" checkout -q -b other
  assert_rc 1 "④ 他 branch acquire 被互斥（等待逾時 exit 1）" \
    env WAVE_LOCK_WAIT_SECONDS=2 WAVE_LOCK_POLL_SECONDS=1 bash "${self}" acquire
  assert_rc 1 "⑤ 非持有 branch release 被拒" bash "${self}" release
  git -C "${tmp}" checkout -q "${db}"
  assert_rc 0 "⑥ 持有 branch release 成功" bash "${self}" release
  [ ! -d "${tmp}/.git/wave-closure.lock" ] \
    && echo "  ✓ ⑦ 釋放後鎖目錄已清" \
    || { echo "  ✗ ⑦ 釋放後鎖目錄仍在"; st_fail=1; }
  git -C "${tmp}" checkout -q other
  assert_rc 0 "⑧ 釋放後他 branch 可取得" bash "${self}" acquire

  # ── 🤖-2 conditional-release ────────────────────────────────
  # 清掉 ⑧ 的鎖
  ( cd "${tmp}" && bash "${self}" release --force ) >/dev/null 2>&1

  # 準備：worktree-wave-test branch 上有 commit
  git -C "${tmp}" checkout -q -b worktree-wave-test
  echo "code" > "${tmp}/test.ts"
  git -C "${tmp}" add test.ts
  git -C "${tmp}" -c user.email=selftest@local -c user.name=selftest \
    commit -q -m "feat: test"
  # 取鎖
  ( cd "${tmp}" && bash "${self}" acquire ) >/dev/null 2>&1

  # ⑨ 持有者已 merge → conditional-release 釋放
  git -C "${tmp}" checkout -q "${db}"
  git -C "${tmp}" merge -q --no-edit worktree-wave-test
  assert_rc 0 "⑨ conditional-release: 持有者已 merge → 釋放" \
    bash "${self}" conditional-release
  [ ! -d "${tmp}/.git/wave-closure.lock" ] \
    && echo "  ✓ ⑨b 鎖已清" \
    || { echo "  ✗ ⑨b 鎖仍在"; st_fail=1; }

  # ⑩ 持有者未 merge → conditional-release 不動鎖
  # 重新取鎖（在 worktree-wave-test 上再加一個 commit）
  git -C "${tmp}" checkout -q worktree-wave-test
  echo "more code" > "${tmp}/test2.ts"
  git -C "${tmp}" add test2.ts
  git -C "${tmp}" -c user.email=selftest@local -c user.name=selftest \
    commit -q -m "feat: more"
  ( cd "${tmp}" && bash "${self}" acquire ) >/dev/null 2>&1
  git -C "${tmp}" checkout -q "${db}"
  # 不 merge，直接跑 conditional-release
  assert_rc 0 "⑩ conditional-release: 持有者未 merge → 不動鎖" \
    bash "${self}" conditional-release
  [ -d "${tmp}/.git/wave-closure.lock" ] \
    && echo "  ✓ ⑩b 鎖保持" \
    || { echo "  ✗ ⑩b 鎖被意外釋放"; st_fail=1; }

  # ── 🤖-3 camp 看門 ──────────────────────────────────────────
  # ⑪ 持鎖 >90 分鐘無 merge → 等待方見警告
  # 偽造 epoch 為 95 分鐘前
  fake_epoch=$(( $(date +%s) - 5700 ))
  printf 'branch=worktree-wave-test\npid=99999\nepoch=%s\ntime=fake\n' \
    "${fake_epoch}" > "${tmp}/.git/wave-closure.lock/info"
  camp_out="$(cd "${tmp}" && \
    env WAVE_LOCK_WAIT_SECONDS=2 WAVE_LOCK_POLL_SECONDS=1 WAVE_LOCK_CAMP_SECONDS=5400 \
    bash "${self}" acquire 2>&1 || true)"
  if echo "${camp_out}" | grep -q "疑似 camp"; then
    echo "  ✓ ⑪ 持鎖 95 分鐘無 merge → 等待方見 camp 警告"
  else
    echo "  ✗ ⑪ 持鎖 95 分鐘無 merge → 未見 camp 警告"
    st_fail=1
  fi

  # ⑫ 持鎖 >90 分鐘但已 merge → 無 camp 警告
  # merge worktree-wave-test 的最新 commit 進 main
  ( cd "${tmp}" && bash "${self}" release --force ) >/dev/null 2>&1
  git -C "${tmp}" merge -q --no-edit worktree-wave-test
  # 重建鎖（偽造舊 epoch）
  mkdir -p "${tmp}/.git/wave-closure.lock"
  printf 'branch=worktree-wave-test\npid=99999\nepoch=%s\ntime=fake\n' \
    "${fake_epoch}" > "${tmp}/.git/wave-closure.lock/info"
  git -C "${tmp}" checkout -q -b another-branch
  camp_out2="$(cd "${tmp}" && \
    env WAVE_LOCK_WAIT_SECONDS=2 WAVE_LOCK_POLL_SECONDS=1 WAVE_LOCK_CAMP_SECONDS=5400 \
    bash "${self}" acquire 2>&1 || true)"
  if echo "${camp_out2}" | grep -q "疑似 camp"; then
    echo "  ✗ ⑫ 持鎖 95 分鐘已 merge → 不該有 camp 警告"
    st_fail=1
  else
    echo "  ✓ ⑫ 持鎖 95 分鐘已 merge → 正確無警告"
  fi

  ( cd "${tmp}" && bash "${self}" release --force ) >/dev/null 2>&1

  if [ "${st_fail}" -eq 0 ]; then
    echo "selftest: PASS（12/12）"
    exit 0
  fi
  echo "selftest: FAIL"
  exit 1
  ;;

*)
  echo "用法: wave-closure-lock.sh {acquire|release [--force]|conditional-release|status|selftest}"
  exit 2
  ;;
esac
