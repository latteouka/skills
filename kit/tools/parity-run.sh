#!/usr/bin/env bash
# parity-run.sh — 隔離 parity harness（K5.5 必修①，K6 Step B 的執行核心）
#
# 母題（GPT-5 總檢 §2）：dfaa 這批腳本大量帶狀態（closure lock、regate stamp、
# preauth、baseline、merge_prep 改依賴），同一 worktree 串行雙跑會互相污染——
# 舊版先跑可能替新版修好環境（消耗 preauth、寫 stamp、tighten baseline），
# 造成新版假等價。解法：從同一 --ref 各自 git clone --no-hardlinks 出 A/B 兩份
# （選 clone 不選 worktree：連 .git 狀態都隔離——lock/stamp/preauth 慣例放
# git-common-dir，worktree 雙掛會共用），各跑各的，五面向對帳。
#
# 用法：
#   bash tools/parity-run.sh --source <git-repo> --ref <commit> \
#     --cmd-a "<舊指令>" --cmd-b "<新指令>" \
#     [--workdir-rel <相對路徑>] [--env KEY=VAL ...] [--state-glob <glob> ...]
#
#   --state-glob 可多次；未指定時預設 `.claude/dev/.wave-*` 與 `.git/wave-*`
#   （kit lock/stamp/preauth 慣例位置：wave-closure.lock/、wave-regate-pass、
#    wave-regate-preauth 皆在 git-common-dir，clone 後即 .git/ 下）。
#
# 五面向（任一不等 → 該面向 DIFF、整體 exit 1）：
#   1/5 exit-code           兩邊 exit code 相等
#   2/5 output(normalized)  stdout＋stderr 正規化後相等（正規化＝各自 clone 根
#                           →<ROOT>、HH:MM[:SS] 時間戳→<TS>、$HOME→<HOME>）
#   3/5 working-tree        git status --porcelain ＋ git diff ＋ git diff --cached
#                           （正規化後）相等
#   4/5 state-glob          逐 glob 比對存在性＋內容（正規化後）
#   5/5 untracked-set       untracked 檔集合（git ls-files --others，含 ignored
#                           ——state 檔常被 .gitignore 蓋住，porcelain 看不到；
#                           排除 state-glob 已比對者）相等
#
# 報告：逐面向 PASS/DIFF（DIFF 附兩邊摘錄，diff 記法 < = A、> = B），
#       尾行 inspected:5 ＋ 整體 PARITY:EQUIV|DIFF。
# exit：0 全等；1 任一面向 DIFF；2 fail-closed（參數缺／--source 非 repo／
#       ref 無法解析／clone 失敗／workdir-rel 不存在／cmd 起不來（exit 126/127
#       視為起不來——被比對腳本自身合法回 126/127 的極端情境不在支援範圍））
set -u
set -o pipefail

fail_closed() { echo "FAIL(closed): ${1}" >&2; exit 2; }

SOURCE=""; REF=""; CMD_A=""; CMD_B=""; WORKDIR_REL="."
ENVS=(); STATE_GLOBS=()

while [ $# -gt 0 ]; do
    case "${1}" in
        --source)      [ $# -ge 2 ] || fail_closed "--source 缺值"; SOURCE="${2}"; shift 2 ;;
        --ref)         [ $# -ge 2 ] || fail_closed "--ref 缺值"; REF="${2}"; shift 2 ;;
        --cmd-a)       [ $# -ge 2 ] || fail_closed "--cmd-a 缺值"; CMD_A="${2}"; shift 2 ;;
        --cmd-b)       [ $# -ge 2 ] || fail_closed "--cmd-b 缺值"; CMD_B="${2}"; shift 2 ;;
        --workdir-rel) [ $# -ge 2 ] || fail_closed "--workdir-rel 缺值"; WORKDIR_REL="${2}"; shift 2 ;;
        --env)         [ $# -ge 2 ] || fail_closed "--env 缺值"
                       # 缺 `=` 的值會被 env 當「要執行的指令」——兩邊對稱地跑錯 → 假 EQUIV
                       case "${2}" in
                           [A-Za-z_]*=*) case "${2%%=*}" in *[!A-Za-z0-9_]*) fail_closed "--env 變數名非法: ${2}" ;; esac ;;
                           *) fail_closed "--env 須為 KEY=VAL 形式（缺 = 會被 env 當指令執行）: ${2}" ;;
                       esac
                       ENVS[${#ENVS[@]}]="${2}"; shift 2 ;;
        --state-glob)  [ $# -ge 2 ] || fail_closed "--state-glob 缺值"; STATE_GLOBS[${#STATE_GLOBS[@]}]="${2}"; shift 2 ;;
        *) fail_closed "未知參數: ${1}" ;;
    esac
done
[ -n "${SOURCE}" ] || fail_closed "--source 必填"
[ -n "${REF}" ]    || fail_closed "--ref 必填"
[ -n "${CMD_A}" ]  || fail_closed "--cmd-a 必填"
[ -n "${CMD_B}" ]  || fail_closed "--cmd-b 必填"
if [ "${#STATE_GLOBS[@]}" -eq 0 ]; then
    STATE_GLOBS=( ".claude/dev/.wave-*" ".git/wave-*" )
fi

git -C "${SOURCE}" rev-parse --git-dir >/dev/null 2>&1 \
    || fail_closed "--source 非 git repo: ${SOURCE}"
git -C "${SOURCE}" rev-parse --verify --quiet "${REF}^{commit}" >/dev/null 2>&1 \
    || fail_closed "--ref 無法解析為 commit: ${REF}（source: ${SOURCE}）"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/parity-run.XXXXXXXX")" || fail_closed "mktemp -d 失敗"
trap 'rm -rf "${WORK}"' EXIT

# --- 隔離雙 clone：起點 git state 完全相同（含 .git——lock/stamp 也歸零）
clone_side() { # <dest>
    local dest="${1}"
    git clone --no-hardlinks --quiet "${SOURCE}" "${dest}" 2>/dev/null \
        || fail_closed "clone 失敗: ${SOURCE} → ${dest}"
    git -C "${dest}" checkout --quiet --detach "${REF}" 2>/dev/null \
        || fail_closed "checkout ${REF} 失敗: ${dest}"
    # 本地 identity：被比對腳本若 commit（如 merge_prep），不依賴全域 git config
    git -C "${dest}" config user.name "parity-run" \
        && git -C "${dest}" config user.email "parity-run@example.invalid" \
        || fail_closed "clone 內 git config 失敗: ${dest}"
}
ROOT_A_LOG="${WORK}/a"; ROOT_B_LOG="${WORK}/b"
clone_side "${ROOT_A_LOG}"
clone_side "${ROOT_B_LOG}"
ROOT_A="$(cd "${ROOT_A_LOG}" && pwd -P)" || fail_closed "無法解析 A clone 根"
ROOT_B="$(cd "${ROOT_B_LOG}" && pwd -P)" || fail_closed "無法解析 B clone 根"
[ -d "${ROOT_A}/${WORKDIR_REL}" ] || fail_closed "--workdir-rel 在 clone 內不存在: ${WORKDIR_REL}"

# --- 正規化（函式化供測試）：clone 根（實體＋邏輯路徑皆換）→<ROOT>、
#     HH:MM:SS / HH:MM →<TS>、$HOME→<HOME>。sed 管線，BRE。
_pr_sed_escape() { printf '%s' "${1}" | sed 's/[][\.*^$/]/\\&/g'; }

parity_normalize() { # <root_phys> <root_log> — stdin→stdout
    local rp rl h
    rp="$(_pr_sed_escape "${1}")"
    rl="$(_pr_sed_escape "${2}")"
    h="$(_pr_sed_escape "${HOME}")"
    sed -e "s/${rp}/<ROOT>/g" -e "s/${rl}/<ROOT>/g" \
        -e "s/${h}/<HOME>/g" \
        -e 's/[0-9][0-9]:[0-9][0-9]:[0-9][0-9]/<TS>/g' \
        -e 's/[0-9][0-9]:[0-9][0-9]/<TS>/g'
}

# --- 各跑各的（cwd=各自 clone 根或 --workdir-rel；exit/stdout/stderr 落檔）
run_side() { # <root> <cmd> <tag>
    local root="${1}" cmd="${2}" tag="${3}" rc=0
    ( cd "${root}/${WORKDIR_REL}" && env ${ENVS[@]+"${ENVS[@]}"} bash -c "${cmd}" ) \
        > "${WORK}/${tag}.out" 2> "${WORK}/${tag}.err" || rc=$?
    case "${rc}" in
        126|127) fail_closed "cmd-${tag} 起不來（exit ${rc}：command not found／不可執行）: ${cmd}" ;;
    esac
    printf '%s' "${rc}" > "${WORK}/${tag}.rc"
}
run_side "${ROOT_A}" "${CMD_A}" a
run_side "${ROOT_B}" "${CMD_B}" b

# --- 對帳素材
# 面向 2：stdout＋stderr（正規化）
collect_output() { # <tag> <root_phys> <root_log>
    { echo "-- stdout"; cat "${WORK}/${1}.out"; echo "-- stderr"; cat "${WORK}/${1}.err"; } \
        | parity_normalize "${2}" "${3}" > "${WORK}/${1}.outerr.n"
}
collect_output a "${ROOT_A}" "${ROOT_A_LOG}"
collect_output b "${ROOT_B}" "${ROOT_B_LOG}"

# 面向 3：working tree 副作用（對 clone 起點；起點＝乾淨 checkout，全差異即副作用）
collect_wt() { # <tag> <root_phys> <root_log>
    { echo "-- status --porcelain"; git -C "${2}" status --porcelain
      echo "-- diff";               git -C "${2}" diff
      echo "-- diff --cached";      git -C "${2}" diff --cached
    } | parity_normalize "${2}" "${3}" > "${WORK}/${1}.wt.n"
}
collect_wt a "${ROOT_A}" "${ROOT_A_LOG}"
collect_wt b "${ROOT_B}" "${ROOT_B_LOG}"

# 面向 4：state-glob 存在性＋內容（正規化）；同時收集已比對相對路徑供面向 5 排除
dump_state() { # <root_phys> <root_log> <dump_out> <matched_list>
    local root="${1}" rlog="${2}" out="${3}" ml="${4}"
    : > "${out}"; : > "${ml}"
    ( cd "${root}" && \
      for g in ${STATE_GLOBS[@]+"${STATE_GLOBS[@]}"}; do
          for f in ${g}; do
              [ -e "${f}" ] || continue
              if [ -d "${f}" ]; then
                  printf '== %s/ (dir)\n' "${f}" >> "${out}"
                  find "${f}" -type f 2>/dev/null | sort | while IFS= read -r sub; do
                      printf '== %s\n' "${sub}" >> "${out}"
                      parity_normalize "${root}" "${rlog}" < "${sub}" >> "${out}"
                      printf '%s\n' "${sub}" >> "${ml}"
                  done
              else
                  printf '== %s\n' "${f}" >> "${out}"
                  parity_normalize "${root}" "${rlog}" < "${f}" >> "${out}"
                  printf '%s\n' "${f}" >> "${ml}"
              fi
          done
      done )
}
dump_state "${ROOT_A}" "${ROOT_A_LOG}" "${WORK}/a.state.n" "${WORK}/a.state.matched"
dump_state "${ROOT_B}" "${ROOT_B_LOG}" "${WORK}/b.state.n" "${WORK}/b.state.matched"

# 面向 5：untracked 檔集合（含 ignored——state 檔常被 .gitignore 蓋住，
# git status --porcelain 看不到，唯此面向抓得到），排除 state-glob 已比對者
collect_untracked() { # <tag> <root_phys>
    git -C "${2}" ls-files --others | sort > "${WORK}/${1}.others"
    sort "${WORK}/${1}.state.matched" > "${WORK}/${1}.state.matched.sorted"
    comm -23 "${WORK}/${1}.others" "${WORK}/${1}.state.matched.sorted" > "${WORK}/${1}.untracked"
}
collect_untracked a "${ROOT_A}"
collect_untracked b "${ROOT_B}"

# --- 五面向對帳報告
echo "== parity-run（source: ${SOURCE} @ ${REF}）"
echo "   A: ${CMD_A}"
echo "   B: ${CMD_B}"
echo "   state-globs: ${STATE_GLOBS[*]}"

N_DIFF=0

report_facet() { # <label> <fileA> <fileB>
    local label="${1}" fa="${2}" fb="${3}"
    if cmp -s "${fa}" "${fb}"; then
        echo "[${label}] PASS"
        return 0
    fi
    echo "[${label}] DIFF（摘錄，< = A、> = B）"
    diff "${fa}" "${fb}" 2>/dev/null | sed -n '1,15p' | sed 's/^/    /'
    N_DIFF=$((N_DIFF + 1))
    return 0
}

RC_A="$(cat "${WORK}/a.rc")"
RC_B="$(cat "${WORK}/b.rc")"
if [ "${RC_A}" = "${RC_B}" ]; then
    echo "[1/5 exit-code] PASS (A=${RC_A} B=${RC_B})"
else
    echo "[1/5 exit-code] DIFF (A=${RC_A} B=${RC_B})"
    N_DIFF=$((N_DIFF + 1))
fi
report_facet "2/5 output(normalized)" "${WORK}/a.outerr.n" "${WORK}/b.outerr.n"
report_facet "3/5 working-tree"       "${WORK}/a.wt.n"     "${WORK}/b.wt.n"
report_facet "4/5 state-glob"         "${WORK}/a.state.n"  "${WORK}/b.state.n"
report_facet "5/5 untracked-set"      "${WORK}/a.untracked" "${WORK}/b.untracked"

echo "inspected:5"
if [ "${N_DIFF}" -gt 0 ]; then
    echo "PARITY:DIFF"
    exit 1
fi
echo "PARITY:EQUIV"
exit 0
