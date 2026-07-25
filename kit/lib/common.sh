#!/usr/bin/env bash
# kit 共用函式庫 — bash 3.2 相容，無外部依賴（jq 為選配）。
# 所有函式 fail-open：找不到資料回 default／空字串，不 exit 非 0（除鎖）。

kit_repo_root() {
    git rev-parse --show-toplevel 2>/dev/null
}

# kit_main_repo_root [override_root]
# 取得「主 checkout」根目錄——多 worktree 情境下，有些產物（inbox.md、
# wave-INDEX.md）是跨 worktree 共用的單一歷史，不該各 worktree 各寫一份
# （否則各自累積、merge 時互相蓋掉對方獨有的紀錄；2026-07-25 實測：dfaa
# 主 checkout + 3 個 worktree，wave-INDEX.md 各處 157/157/157/6 行，已分裂
# 到無法合併）。
#
# 邏輯：先取 kit_repo_root；若該路徑含 `/.claude/worktrees/`，截斷到該段
# 之前即為主 checkout 路徑。巢狀 worktree（路徑含多層 .claude/worktrees/）
# 一律截到「第一個」出現的位置——bash `${var%%pattern}` 對含萬用字元的
# pattern 本來就會匹配「最長的符合後綴」，等同於從最左邊（最外層）那個
# `/.claude/worktrees/` 開始截，不需要額外邏輯。
#
# fail-open：算出的主 checkout 路徑若不存在、或不是 git repo，一律回退
# 用原路徑（$root 本身，即目前所在的 worktree）——絕不回空字串，避免
# 呼叫端把空字串當成「不在任何 repo 內」而整段跳過寫入。
#
# override_root 僅供測試注入路徑字串（避免建立真正巢狀 git worktree的
# 複雜度）；正常呼叫不帶參數，用 kit_repo_root 即時偵測。
kit_main_repo_root() {
    local root="${1:-}" main
    [ -n "$root" ] || root="$(kit_repo_root)"
    [ -n "$root" ] || return 0

    case "$root" in
        */.claude/worktrees/*)
            main="${root%%/.claude/worktrees/*}"
            if [ -n "$main" ] && [ -d "$main" ] && git -C "$main" rev-parse --show-toplevel >/dev/null 2>&1; then
                printf '%s' "$main"
            else
                printf '%s' "$root"
            fi
            ;;
        *)
            printf '%s' "$root"
            ;;
    esac
}

# _kit_unquote_value <raw>
# 內部共用函式：對「key: value」的 value 部分去行內註解＋去頭尾成對引號。
# 供 kit_config_get / kit_fm_get 共用，避免同一個 sed idiom 各複製一份、
# 修一次漏一處（2026-07-25 行內註解 bug 的根因就是這段邏輯散在兩處各自實作）。
#
# 規則（對齊 YAML 語意）：
#   - value 若以引號開頭（單/雙皆可），取到「下一個同款引號」為止，引號內的
#     空白與 # 一律視為值的一部分，不當註解處理（不然帶空格的指令字串會被截斷）。
#   - value 未加引號時，`#` 前面需緊接空白（或整段即以 # 開頭）才視為註解起點；
#     沒有前置空白的 # 是值本身的一部分（YAML 規範如此，如 `foo#bar` 整串是值）。
#   - 去註解必須先做，再去尾空白（去註解會在值尾端留下原本註解前的空白）。
_kit_unquote_value() {
    local raw="$1" val
    case "$raw" in
        \"*)
            val="${raw#\"}"
            val="${val%%\"*}"
            ;;
        \'*)
            val="${raw#\'}"
            val="${val%%\'*}"
            ;;
        *)
            val="$(printf '%s\n' "$raw" | sed 's/^#.*$//; s/[[:blank:]]#.*$//')"
            val="$(printf '%s\n' "$val" | sed 's/[[:space:]]*$//')"
            ;;
    esac
    printf '%s' "$val"
}

# kit_config_get <key> <default>
# 讀 <repo>/.claude/dev/intake.config.yaml 的 top-level key。
# 只支援 `key: value` 平鋪格式（本 kit 的 config 刻意保持平鋪），支援行內註解與引號值。
kit_config_get() {
    local key="$1" default="${2:-}" root cfg raw val
    root="$(kit_repo_root)" || { printf '%s' "$default"; return 0; }
    cfg="${root}/.claude/dev/intake.config.yaml"
    [ -f "$cfg" ] || { printf '%s' "$default"; return 0; }
    raw="$(sed -n "s/^${key}:[[:space:]]*//p" "$cfg" | sed -n '1p')"
    val="$(_kit_unquote_value "$raw")"
    [ -n "$val" ] || val="$default"
    printf '%s' "$val"
}

# kit_fm_get <file> <key>
# 讀 YAML frontmatter（首行必須是 --- ，到下一個 --- 為止）的欄位。
# 必須有成對的 --- （開頭與結尾）才解析；否則回空字串，絕不誤讀內文。
# 同 kit_config_get，支援行內註解與引號值（見 _kit_unquote_value）。
kit_fm_get() {
    local file="$1" key="$2" first has_closing raw
    [ -f "$file" ] || return 0
    first="$(sed -n '1p' "$file")"
    [ "$first" = "---" ] || return 0
    # 確認真的有結尾的 ---（不只開頭）
    has_closing="$(sed -n '2,$p' "$file" | grep -n '^---$' | head -1)"
    [ -n "$has_closing" ] || return 0
    raw="$(sed -n '2,/^---$/p' "$file" \
        | sed -n "s/^${key}:[[:space:]]*//p" \
        | sed -n '1p')"
    _kit_unquote_value "$raw"
}

# kit_next_id <file> <prefix>
# 掃檔案取 <prefix>-NNN 的最大值 +1，補三位數。空檔／缺檔回 <prefix>-001。
#
# 只認「## <prefix>-NNN」標題行（條目本身），不掃整檔——內文引用既有編號
# （如「這跟 INB-042 是同一個問題」、backlog.md 的「from: INB-042」）不是
# 條目，不該被算進最大值，否則會把下一號劫持掉（2026-07-25 修正：舊版
# grep -o 全檔掃描，行內任何 INB-NNN 字面值都會誤判成條目）。
kit_next_id() {
    local file="$1" prefix="$2" max
    max=0
    if [ -f "$file" ]; then
        max="$(grep -o "^## ${prefix}-[0-9][0-9]*" "$file" 2>/dev/null \
            | sed "s/^## ${prefix}-//" \
            | sort -n \
            | tail -1)"
        [ -n "$max" ] || max=0
    fi
    printf '%s-%03d' "$prefix" "$((10#$max + 1))"
}

# kit_lock_acquire <lockdir> [max_tries]
# mkdir 為 POSIX 原子操作，用於取代 macOS 沒有的 flock。
# 每次重試間隔 0.1 秒；預設 20 次（2 秒）後放棄回 1。
kit_lock_acquire() {
    local lockdir="$1" max_tries="${2:-20}" tries=0
    while ! mkdir "$lockdir" 2>/dev/null; do
        tries=$((tries + 1))
        if [ "$tries" -ge "$max_tries" ]; then return 1; fi
        sleep 0.1
    done
    return 0
}

kit_lock_release() {
    rmdir "$1" 2>/dev/null || true
}
