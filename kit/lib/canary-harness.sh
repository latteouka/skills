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

# canary_stub_gate_name <tier> <stub_path> — gates.d stub → canary.d fixture
# 名稱推導：gates.d/<tier>.d/NN-<name>.sh → canary.d/<tier>-<name>/
# （去 NN- 字典序前綴與 .sh 副檔名，前綴 tier 避免 tierA/tierB 同名 stub 撞名）。
canary_stub_gate_name() {
    local tier="${1}" stub="${2}" base name
    base="$(basename "${stub}")"
    name="${base%.sh}"
    name="$(printf '%s\n' "${name}" | sed -n 's/^[0-9][0-9]*-//p')"
    [ -n "${name}" ] || name="${base%.sh}"
    printf '%s-%s' "${tier}" "${name}"
}

# canary_reconcile_gates <decl_dir> — gates.d↔canary.d 對帳（K5.5 GPT §4.3）。
#
# 母題：canary.d 只列舉自己有的目錄，一支 gates.d 有 stub 但沒人補 canary
# fixture 的 gate 永遠不會被三斷言測到——「漏測」與「測過全綠」在引擎輸出
# 上長得一樣。本函式反過來，以 gates.d 的 stub 清單為準逐一核對 canary.d
# 是否有對應 fixture。
#
# 命名對應規則：gates.d/tierA.d/NN-<name>.sh → canary.d/tierA-<name>/；
# tierB.d 同理 → canary.d/tierB-<name>/（見 canary_stub_gate_name）。
#
# 豁免契約：無法補 fixture 的 gate 需逐一放 canary.d/<gate>.skip marker
# 檔，內容必須非空白（理由一行）。理由留空＝無效豁免，視同未豁免照樣 FAIL
# （fail-closed——不許用空檔繞過對帳）。
#
# gates.d 整體不存在（專案未裝 wave-gate 模組，只用 canary 跑其他自訂
# gate）→ 印 SKIP 明示、return 0，不誤殺。
#
# stdout：逐項 ✗/⚠ 訊息（呼叫端自行決定要不要轉印）。
# return：0＝全數有 fixture 或已豁免（或 gates.d 不存在）；1＝至少一項缺
# fixture 且未豁免（呼叫端據此列 FAIL、exit 1）。
canary_reconcile_gates() {
    local decl_dir="${1}" gates_d canary_d tier tier_dir stub gate_name skip_marker reason failed=0
    gates_d="${decl_dir}/gates.d"
    canary_d="${decl_dir}/canary.d"
    if [ ! -d "${gates_d}" ]; then
        echo "SKIP(gates.d↔canary.d 對帳): gates.d 不存在 [${gates_d}]——本專案未用 wave-gate 模組"
        return 0
    fi
    for tier in tierA tierB; do
        tier_dir="${gates_d}/${tier}.d"
        [ -d "${tier_dir}" ] || continue
        for stub in "${tier_dir}"/*.sh; do
            [ -f "${stub}" ] || continue
            gate_name="$(canary_stub_gate_name "${tier}" "${stub}")"
            if [ -d "${canary_d}/${gate_name}" ]; then
                continue
            fi
            skip_marker="${canary_d}/${gate_name}.skip"
            if [ -f "${skip_marker}" ]; then
                reason="$(tr -d '[:space:]' < "${skip_marker}" 2>/dev/null)"
                if [ -n "${reason}" ]; then
                    echo "  ⚠ 對帳: ${gate_name} 已豁免（.skip 理由: $(cat "${skip_marker}")）"
                    continue
                fi
                echo "  ✗ 對帳: ${gate_name} 缺 canary.d fixture，.skip 理由為空（無效豁免）[${skip_marker}]"
                failed=1
                continue
            fi
            echo "  ✗ 對帳: gates.d stub [${stub}] 缺對應 canary.d fixture [${canary_d}/${gate_name}]（未豁免）"
            failed=1
        done
    done
    return "${failed}"
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
