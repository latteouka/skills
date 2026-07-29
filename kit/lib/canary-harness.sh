#!/usr/bin/env bash
# canary-harness.sh — gate 自測三斷言核心（自 dfaa scripts/hooks/__tests__/canary.sh 抽出通用層）
#
# 母題（上游 commit 7c904ee47 的 8 天空轉 bug）：.husky/pre-push 首行 cd apps/web 後
# pathspec 仍寫 repo-root 相對 → 恆 0 命中 → typecheck/lint/test 每次 push 綠燈但實際
# 檢查 0 個檔。gate 沒壞、exit code 沒錯——「假 PASS」最陰險的形態。本 harness 把偵測
# 機器化：每支 gate 配 violation/clean 雙 fixture，跑一次證明它「真的有檢查東西」。
#
# 三斷言（缺一不可）：
#   1. violation fixture → gate exit ≠ 0
#   2. clean fixture（語意相近但合法，非隨便空檔）→ gate exit 0
#   3. inspected:N 且 N>0——取不到標 UNAVAILABLE 並 FAIL，不得靜默當過
#
# fail-closed 定位：gate script 不存在／無執行權限／fixture 缺失 → 明確 FAIL 並指名。
#
# 自衝突 fixture 解法（上游 2026-07-25 修）：violation fixture 若用真實副檔名躺在
# repo 裡，會被「它自己要測試的 gate」在 pre-commit/pre-push 攔下。解法＝repo 內
# 存成 <真檔名>.fixture，複製進 scratch 時還原真檔名——gate 收到完整未修改的違規
# 內容，判斷邏輯全程真實執行。不用「gate 豁免 fixtures/」——那會讓 violation 斷言
# 恆假陽性（gate 沒攔任何東西，只是被自己的豁免放行）。
#
# 冪等 stdout 紀律：只印衍生訊號（exit code／inspected 數字），絕不印 gate 原始輸出
# ——連跑兩次 stdout 逐字一致，不受 mktemp 隨機路徑影響。
#
# bash 3.2 相容：一律 ${var}；不用 declare -A / mapfile / ${var,,}；mktemp -d 原子建立。

set -u
set -o pipefail

# canary_tmp_init [prefix] — 建隔離工作目錄並掛 EXIT 清理。輸出路徑。
canary_tmp_init() {
    local prefix="${1:-kit-gate-canary}" d
    d="$(mktemp -d "${TMPDIR:-/tmp}/${prefix}.XXXXXXXX")" || {
        echo "canary: mktemp -d 失敗，無法建立隔離工作目錄，拒絕通過" >&2
        return 1
    }
    printf '%s' "${d}"
}

# canary_require_gate <name> <path> — gate 不存在／無執行權限 → FAIL 指名
canary_require_gate() {
    local name="${1}" path="${2}"
    if [ ! -f "${path}" ]; then
        echo "  ✗ ${name}: gate script 不存在 [${path}]"
        return 1
    fi
    if [ ! -x "${path}" ]; then
        echo "  ✗ ${name}: gate script 無執行權限 [${path}]（chmod +x 後重跑）"
        return 1
    fi
    return 0
}

# canary_require_fixture <name> <path> [repo_root] — fixture 缺失／未進版控 → FAIL。
# repo_root 給了才做版控檢查（上游 require_fixture_tracked 事故：.gitignore 全域
# *.yaml 吃掉 fixture，本機綠、clone 紅——「canary 綠得有理由，但理由是本機殘留」。
# 檔案存在性擋不到，必須查版控狀態）。scratch 環境（測試自身）不帶 repo_root 跳過。
canary_require_fixture() {
    local name="${1}" path="${2}" repo_root="${3:-}"
    if [ ! -e "${path}" ]; then
        echo "  ✗ ${name}: fixture 缺失 [${path}]"
        return 1
    fi
    [ -n "${repo_root}" ] || return 0
    local untracked
    untracked="$(cd "${repo_root}" && git ls-files --others --ignored --exclude-standard -- "${path}" 2>/dev/null)"
    if [ -n "${untracked}" ]; then
        echo "  ✗ ${name}: fixture 存在於本機但未進版控（被 .gitignore 吃掉），其他 checkout 拿不到 → 此處綠燈是假的。git add -f 收進去："
        printf '       %s\n' ${untracked}
        return 1
    fi
    untracked="$(cd "${repo_root}" && git ls-files --others --exclude-standard -- "${path}" 2>/dev/null)"
    if [ -n "${untracked}" ]; then
        echo "  ✗ ${name}: fixture 未進版控（未 git add）："
        printf '       %s\n' ${untracked}
        return 1
    fi
    return 0
}

# canary_new_scratch_repo <dir> — 隔離 git repo（local identity，不寫全域 config）
canary_new_scratch_repo() {
    local dir="${1}"
    mkdir -p "${dir}" || return 1
    ( cd "${dir}" && git init -q ) || return 1
    ( cd "${dir}" && git config user.name "gate-canary" && git config user.email "gate-canary@example.invalid" ) || return 1
    return 0
}

# canary_seed_origin_main <dir> — 初始 commit + 字面名 origin/main 本地分支。
# gitrevisions(7) 解析序 refs/heads/origin/main 先於 refs/remotes/——不需真 remote，
# 依賴 origin/main 的 gate 在 scratch repo 內即可解析（建出來，非靜默 SKIP）。
canary_seed_origin_main() {
    local dir="${1}"
    ( cd "${dir}" \
        && echo "gate-canary seed" > .gate-canary-seed \
        && git add .gate-canary-seed \
        && git commit -q -m "gate-canary: seed" \
        && git branch origin/main )
}

# canary_copy_fixture_tree <src_dir> <dest> — 整棵樹複製（保留相對路徑），
# 並把 *.fixture 還原真檔名（自衝突 fixture 遮蔽機制的還原側）。
canary_copy_fixture_tree() {
    local src="${1}" dest="${2}" f base
    if [ ! -d "${src}" ]; then
        echo "  ✗ fixture 目錄缺失 [${src}]"
        return 1
    fi
    mkdir -p "${dest}" || return 1
    cp -R "${src}/." "${dest}/" || return 1
    # .fixture 還原（find 深度不限；bash 3.2 無 globstar）
    find "${dest}" -name '*.fixture' -type f | while IFS= read -r f; do
        mv "${f}" "${f%.fixture}"
    done
    return 0
}

# canary_extract_inspected <output> — 從 gate 輸出抽 inspected:N。取不到印
# UNAVAILABLE 理由並 return 1（斷言 3 的 fail-closed 面）。
canary_extract_inspected() {
    local output="${1}" n
    n="$(printf '%s\n' "${output}" | sed -n 's/.*inspected:\([0-9][0-9]*\).*/\1/p' | head -1)"
    if [ -z "${n}" ]; then
        echo "inspected:UNAVAILABLE(gate 輸出無 inspected:N)"
        return 1
    fi
    printf '%s' "${n}"
    return 0
}

# canary_run_gate <name> <gate_cmd> <violation_dir> <clean_dir> [tmp_root]
# 三斷言一次跑完。gate_cmd 以「fixture 複製出的 scratch 目錄」為 cwd 執行
# （eval 執行，可含參數）。回 0=三斷言全過；非 0=至少一敗（已印明細）。
canary_run_gate() {
    local name="${1}" gate_cmd="${2}" vdir="${3}" cdir="${4}" tmp_root="${5:-}"
    local ok=0 scratch out rc inspected

    [ -n "${tmp_root}" ] || { tmp_root="$(canary_tmp_init)" || return 1; }

    # 斷言 1：violation 必紅
    scratch="${tmp_root}/${name}/violation"
    canary_copy_fixture_tree "${vdir}" "${scratch}" || return 1
    out="$( (cd "${scratch}" && eval "${gate_cmd}") 2>&1 )"
    rc=$?
    if [ "${rc}" -eq 0 ]; then
        echo "  ✗ ${name}: violation fixture 未被攔（exit 0）"
        ok=1
    else
        echo "  ✓ ${name}: violation:caught (exit ${rc})"
    fi

    # 斷言 3：violation 輸出須有 inspected:N>0
    inspected="$(canary_extract_inspected "${out}")" || {
        echo "  ✗ ${name}: ${inspected:-inspected:UNAVAILABLE}"
        ok=1
    }
    if [ -n "${inspected}" ] && [ "${inspected}" -eq 0 ] 2>/dev/null; then
        echo "  ✗ ${name}: inspected:0——gate 跑了但檢查了 0 個檔（假 PASS 母題）"
        ok=1
    fi

    # 斷言 2：clean 必綠
    scratch="${tmp_root}/${name}/clean"
    canary_copy_fixture_tree "${cdir}" "${scratch}" || return 1
    out="$( (cd "${scratch}" && eval "${gate_cmd}") 2>&1 )"
    rc=$?
    if [ "${rc}" -ne 0 ]; then
        echo "  ✗ ${name}: clean fixture 被誤攔（exit ${rc}）"
        ok=1
    else
        echo "  ✓ ${name}: clean:pass"
    fi

    return "${ok}"
}
