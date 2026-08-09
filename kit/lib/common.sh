#!/usr/bin/env bash
# kit 共用函式庫 — bash 3.2 相容，無外部依賴（jq 為選配）。
# 所有函式 fail-open：找不到資料回 default／空字串，不 exit 非 0。

# _kit_unquote_value <raw>
# 內部共用函式：對「key: value」的 value 部分去行內註解＋去頭尾成對引號。
# 集中一處實作，避免同一個 sed idiom 各複製一份、修一次漏一處
# （2026-07-25 行內註解 bug 的根因就是這段邏輯散在兩處各自實作）。
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

# kit_decl_get <file> <key> [default]
# 讀任意 flat-key YAML 宣告檔（如專案 .claude/kit/kit.yaml）的 top-level key。
# 支援行內註解與引號值（見 _kit_unquote_value）。
# 兩態語意（「欄位留空＝該功能降級」的實作面）：
#   - key 存在但值為空（`key: ""` 或 `key:` 後無值）→ 回空字串——宣告者
#     主動留空＝降級，不得被 default 蓋掉（GPT-5 總檢：舊版把兩態都轉
#     default，空 matrix_dir 仍變回預設路徑，降級語意失效）。
#   - key 完全缺席／檔案缺失 → 回 default（fail-open）。
# TS 側同構實作：engines/rtm-check.ts declGet，語意改動必兩側同改。
kit_decl_get() {
    local file="$1" key="$2" default="${3:-}" raw
    [ -f "$file" ] || { printf '%s' "$default"; return 0; }
    grep -q "^${key}:" "$file" 2>/dev/null || { printf '%s' "$default"; return 0; }
    raw="$(sed -n "s/^${key}:[[:space:]]*//p" "$file" | sed -n '1p')"
    _kit_unquote_value "$raw"
}
