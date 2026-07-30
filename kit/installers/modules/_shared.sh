#!/usr/bin/env bash
# modules/_shared.sh — installer 模組共用函式（K4 起；K5 的 --rtm/--wave-gates 模組沿用）。
# 使用慣例：模組先 source lib/common.sh 再 source 本檔；開頭呼叫 kit_module_begin，
# 各 scaffold/merge 函式把結果累積到 KIT_MODULE_CREATED / KIT_MODULE_SKIPPED，
# 結尾呼叫 kit_module_report 統一輸出。全部冪等：已存在／已安裝一律 skip 不覆寫。
# bash 3.2 相容，無外部依賴（settings merge 需 jq）。

KIT_MODULE_CREATED=""
KIT_MODULE_SKIPPED=""

kit_module_begin() {
    KIT_MODULE_CREATED=""
    KIT_MODULE_SKIPPED=""
}

# kit_scaffold_dir <dir> [name]
# 宣告式建目錄：存在→skip，不存在→mkdir -p。
kit_scaffold_dir() {
    local dir="$1" name="${2:-$1}"
    if [ -d "$dir" ]; then
        KIT_MODULE_SKIPPED="${KIT_MODULE_SKIPPED} ${name}"
    else
        mkdir -p "$dir"
        KIT_MODULE_CREATED="${KIT_MODULE_CREATED} ${name}"
    fi
}

# kit_scaffold_file <src> <dest> [name]
# 宣告式安裝檔案：dest 已存在→skip 不覆寫（與 intake.sh install_file 同語意）。
kit_scaffold_file() {
    local src="$1" dest="$2" name="${3:-$2}"
    if [ -f "$dest" ]; then
        KIT_MODULE_SKIPPED="${KIT_MODULE_SKIPPED} ${name}"
    else
        cp "$src" "$dest"
        KIT_MODULE_CREATED="${KIT_MODULE_CREATED} ${name}"
    fi
}

# kit_module_settings_merge <settings.json> <sentinel> <jq-filter>
# settings.json 合法性驗證 → sentinel 已存在則 skip（冪等）→ 備份 → jq merge 原子寫入。
# sentinel＝merge 後必然出現在檔內的字串（如 hook 指令路徑），用它判斷「已安裝」。
# 回 1＝環境不符（缺 jq／壞 JSON），呼叫端自行決定中止或降級。
kit_module_settings_merge() {
    local settings="$1" sentinel="$2" filter="$3" tmp
    command -v jq >/dev/null 2>&1 || { echo "錯誤：settings merge 需要 jq。" >&2; return 1; }
    [ -f "$settings" ] || printf '{}\n' > "$settings"
    if ! jq empty "$settings" >/dev/null 2>&1; then
        echo "錯誤：${settings} 不是合法 JSON，不做 merge。" >&2
        return 1
    fi
    if grep -qF "$sentinel" "$settings" 2>/dev/null; then
        KIT_MODULE_SKIPPED="${KIT_MODULE_SKIPPED} settings.json(已安裝)"
        return 0
    fi
    cp "$settings" "${settings}.bak-$(date '+%Y%m%d%H%M%S')"
    tmp="$(mktemp)"
    jq "$filter" "$settings" > "$tmp" && mv "$tmp" "$settings"
    KIT_MODULE_CREATED="${KIT_MODULE_CREATED} settings.json"
}

# kit_module_husky_marker <repo_root> <hook> <module> <content>
# 對 .husky/<hook> 插入 kit marker 段（實際寫入委給 lib/common.sh 的 kit_marker_block，
# 冪等且不動專案自有內容）。區塊已存在且內容相同→skip 且完全不重寫檔案
# （保「跑兩次 diff 零」；kit_marker_block 雖冪等但會 rewrite 檔案）。
kit_module_husky_marker() {
    local root="$1" hook="$2" module="$3" content="$4"
    local file="${root}/.husky/${hook}" start end expected current
    start="# >>> kit:${module} >>>"
    end="# <<< kit:${module} <<<"
    mkdir -p "${root}/.husky"
    if [ -f "$file" ] && grep -qxF "$start" "$file" 2>/dev/null; then
        expected="$(printf '%s\n%s\n%s' "$start" "$content" "$end")"
        current="$(awk -v s="$start" -v e="$end" '$0==s{f=1} f{print} $0==e{f=0}' "$file")"
        if [ "$current" = "$expected" ]; then
            KIT_MODULE_SKIPPED="${KIT_MODULE_SKIPPED} .husky/${hook}(kit:${module})"
            return 0
        fi
    fi
    kit_marker_block "$file" "$module" "$content"
    chmod +x "$file" 2>/dev/null || true
    KIT_MODULE_CREATED="${KIT_MODULE_CREATED} .husky/${hook}(kit:${module})"
}

# kit_module_report <module-name>
kit_module_report() {
    local name="$1"
    echo "✅ ${name} 模組安裝完成"
    [ -n "$KIT_MODULE_CREATED" ] && echo "  新建：${KIT_MODULE_CREATED}"
    [ -n "$KIT_MODULE_SKIPPED" ] && echo "  跳過（已存在）：${KIT_MODULE_SKIPPED}"
    return 0
}
