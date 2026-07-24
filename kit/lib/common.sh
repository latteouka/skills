#!/usr/bin/env bash
# kit 共用函式庫 — bash 3.2 相容，無外部依賴（jq 為選配）。
# 所有函式 fail-open：找不到資料回 default／空字串，不 exit 非 0（除鎖）。

kit_repo_root() {
    git rev-parse --show-toplevel 2>/dev/null
}

# kit_config_get <key> <default>
# 讀 <repo>/.claude/dev/intake.config.yaml 的 top-level key。
# 只支援 `key: value` 平鋪格式（本 kit 的 config 刻意保持平鋪）。
kit_config_get() {
    local key="$1" default="${2:-}" root cfg val
    root="$(kit_repo_root)" || { printf '%s' "$default"; return 0; }
    cfg="${root}/.claude/dev/intake.config.yaml"
    [ -f "$cfg" ] || { printf '%s' "$default"; return 0; }
    val="$(sed -n "s/^${key}:[[:space:]]*//p" "$cfg" | sed -n '1p' | sed 's/[[:space:]]*$//')"
    [ -n "$val" ] || val="$default"
    printf '%s' "$val"
}

# kit_fm_get <file> <key>
# 讀 YAML frontmatter（首行必須是 --- ，到下一個 --- 為止）的欄位。
# 無 frontmatter 時回空字串，絕不誤讀內文。
kit_fm_get() {
    local file="$1" key="$2" first
    [ -f "$file" ] || return 0
    first="$(sed -n '1p' "$file")"
    [ "$first" = "---" ] || return 0
    sed -n '2,/^---$/p' "$file" \
        | sed -n "s/^${key}:[[:space:]]*//p" \
        | sed -n '1p' \
        | sed 's/[[:space:]]*$//'
}

# kit_next_id <file> <prefix>
# 掃檔案取 <prefix>-NNN 的最大值 +1，補三位數。空檔／缺檔回 <prefix>-001。
kit_next_id() {
    local file="$1" prefix="$2" max
    max=0
    if [ -f "$file" ]; then
        max="$(grep -o "${prefix}-[0-9][0-9]*" "$file" 2>/dev/null \
            | sed "s/${prefix}-//" \
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
