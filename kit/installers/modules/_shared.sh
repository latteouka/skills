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

# kit_guard_worktree_install — KIT_ROOT 在 worktree 內＝路徑會隨清除失效（hook 指死路徑
# 鎖死全 repo commit/push）。拒裝；測試用 KIT_INIT_ALLOW_WORKTREE=1 豁免。
kit_guard_worktree_install() {
    local kr="$1"
    case "$kr" in
        */.claude/worktrees/*)
            if [ "${KIT_INIT_ALLOW_WORKTREE:-0}" != "1" ]; then
                echo "錯誤：不可從 worktree 安裝（KIT_ROOT=${kr} 會隨 worktree 清除失效）。請從主 checkout 執行。" >&2
                return 1
            fi
            ;;
    esac
    return 0
}

# kit_module_settings_merge <settings.json> <sentinel> <jq-filter>
# settings.json 合法性驗證 → sentinel 已存在則 skip（冪等）→ 備份 → jq merge 原子寫入。
# sentinel＝merge 後必然出現在檔內的字串（如 hook 指令路徑），用它判斷「已安裝」。
# 回 1＝環境不符（缺 jq／壞 JSON），呼叫端自行決定中止或降級。
kit_module_settings_merge() {
    local settings="$1" sentinel="$2" filter="$3" tmp
    command -v jq >/dev/null 2>&1 || { echo "錯誤：settings merge 需要 jq。" >&2; return 1; }
    [ -f "$settings" ] || printf '{}\n' > "$settings"
    if ! jq -e 'type=="object"' "$settings" >/dev/null 2>&1; then
        echo "錯誤：${settings} 不是合法 JSON object（空檔/array/字串皆拒），不做 merge。" >&2
        return 1
    fi
    if grep -qF "$sentinel" "$settings" 2>/dev/null; then
        KIT_MODULE_SKIPPED="${KIT_MODULE_SKIPPED} settings.json(已安裝)"
        return 0
    fi
    cp "$settings" "${settings}.bak-$(date '+%Y%m%d%H%M%S').$$" || { echo "錯誤：settings 備份失敗，不做 merge。" >&2; return 1; }
    tmp="${settings}.tmp.$$"
    if ! jq "$filter" "$settings" > "$tmp" 2>/dev/null; then
        echo "錯誤：jq merge 失敗（filter 或磁碟問題），settings 未變更。" >&2
        rm -f "$tmp"; return 1
    fi
    if ! jq -e 'type=="object"' "$tmp" >/dev/null 2>&1; then
        echo "錯誤：merge 產物不是合法 JSON object，拒絕覆寫。" >&2
        rm -f "$tmp"; return 1
    fi
    mv "$tmp" "$settings" || { rm -f "$tmp"; return 1; }
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

# kit_scaffold_content <dest> <name> <content>
# 宣告式安裝「生成內容」檔（無 template 來源、內容含安裝時展開的 kit 路徑）。
# dest 已存在→skip 不覆寫（與 kit_scaffold_file 同語意）。
kit_scaffold_content() {
    local dest="$1" name="$2" content="$3"
    if [ -f "$dest" ]; then
        KIT_MODULE_SKIPPED="${KIT_MODULE_SKIPPED} ${name}"
    else
        printf '%s\n' "$content" > "$dest"
        KIT_MODULE_CREATED="${KIT_MODULE_CREATED} ${name}"
    fi
}

# kit_module_ensure_kit_yaml <repo_root> <kit_root>
# <repo>/.claude/kit/kit.yaml 不存在 → 從 templates/kit.yaml 建立並把 kit_root
# 寫死為安裝時的 kit 絕對路徑；已存在→skip 不覆寫（使用者手寫的部分宣告
# 由各模組的 kit_module_decl_key 補缺 key，不動既有值）。
kit_module_ensure_kit_yaml() {
    local root="$1" kit_root="$2" dest="$1/.claude/kit/kit.yaml"
    mkdir -p "${root}/.claude/kit"
    if [ -f "$dest" ]; then
        KIT_MODULE_SKIPPED="${KIT_MODULE_SKIPPED} kit.yaml"
    else
        sed "s|^kit_root: .*|kit_root: \"${kit_root}\"|" \
            "${kit_root}/templates/kit.yaml" > "$dest"
        KIT_MODULE_CREATED="${KIT_MODULE_CREATED} kit.yaml"
    fi
}

# kit_module_decl_key <repo_root> <key> <default>
# kit.yaml 缺該 top-level key 才 append（既有 kit.yaml 可能是使用者手寫的
# 部分宣告）；key 已存在一律不動（含值為空——留空是合法的降級宣告）。
kit_module_decl_key() {
    local root="$1" key="$2" default="$3" f="${root}/.claude/kit/kit.yaml"
    grep -q "^${key}:" "$f" 2>/dev/null && return 0
    printf '%s: "%s"\n' "$key" "$default" >> "$f"
    KIT_MODULE_CREATED="${KIT_MODULE_CREATED} kit.yaml(+${key})"
}

# kit_module_register <repo_root> <module>
# 把模組名登記進 kit.yaml 的 modules 清單（空白分隔）。已含該名→skip 且
# 不重寫檔案（冪等 diff 零）。modules 行不存在→append。
kit_module_register() {
    local root="$1" name="$2" f="${root}/.claude/kit/kit.yaml" mods tmp
    mods="$(kit_decl_get "$f" modules '')"
    case " ${mods} " in
        *" ${name} "*)
            KIT_MODULE_SKIPPED="${KIT_MODULE_SKIPPED} kit.yaml(modules已含${name})"
            return 0
            ;;
    esac
    if [ -n "$mods" ]; then mods="${mods} ${name}"; else mods="${name}"; fi
    if grep -q '^modules:' "$f" 2>/dev/null; then
        tmp="${f}.kit-reg.$$"
        KIT_REG_MODS="$mods" awk '
            !done && /^modules:/ { printf "modules: \"%s\"\n", ENVIRON["KIT_REG_MODS"]; done = 1; next }
            { print }
        ' "$f" > "$tmp" && mv "$tmp" "$f"
    else
        printf 'modules: "%s"\n' "$mods" >> "$f"
    fi
    KIT_MODULE_CREATED="${KIT_MODULE_CREATED} kit.yaml(modules+=${name})"
}

# kit_module_gitignore <repo_root> <section_comment> <line>...
# .gitignore 逐行冪等 append（整行精確比對）；本輪真的有新增行才補段落
# 註解（段落註解已存在也不重複）。
kit_module_gitignore() {
    local root="$1" section="$2" gitignore="${root}/.gitignore" added="" line
    shift 2
    [ -f "$gitignore" ] || : > "$gitignore"
    for line in "$@"; do
        grep -qxF "$line" "$gitignore" 2>/dev/null && continue
        if [ -z "$added" ] && ! grep -qF "# ${section}" "$gitignore" 2>/dev/null; then
            printf '\n# %s\n' "$section" >> "$gitignore"
        fi
        printf '%s\n' "$line" >> "$gitignore"
        added="${added} ${line}"
    done
    if [ -n "$added" ]; then
        KIT_MODULE_CREATED="${KIT_MODULE_CREATED} .gitignore(新增${added})"
    else
        KIT_MODULE_SKIPPED="${KIT_MODULE_SKIPPED} .gitignore(已含全部條目)"
    fi
}

# kit_module_report <module-name>
kit_module_report() {
    local name="$1"
    echo "✅ ${name} 模組安裝完成"
    [ -n "$KIT_MODULE_CREATED" ] && echo "  新建：${KIT_MODULE_CREATED}"
    [ -n "$KIT_MODULE_SKIPPED" ] && echo "  跳過（已存在）：${KIT_MODULE_SKIPPED}"
    return 0
}
