#!/usr/bin/env bash
# /kit-init --intake 實作。冪等：已存在的檔案與 hook 條目一律跳過不覆寫。
#
# --non-interactive：跳過提問，全用預設值（測試與自動化用）。

set -u

KIT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "${KIT_ROOT}/lib/common.sh" 2>/dev/null || { echo "找不到 lib/common.sh"; exit 1; }

NONINTERACTIVE=false
for a in "$@"; do
    case "$a" in --non-interactive) NONINTERACTIVE=true ;; esac
done

root="$(kit_repo_root)"
if [ -z "$root" ]; then echo "錯誤：不在 git repo 內，無法安裝。"; exit 1; fi

command -v jq >/dev/null 2>&1 || { echo "錯誤：需要 jq。"; exit 1; }

# --- 前置檢查：settings.json 合法性（所有寫入前驗證）
settings="${root}/.claude/settings.json"
mkdir -p "${root}/.claude"
[ -f "$settings" ] || printf '{}\n' > "$settings"

if ! jq empty "$settings" >/dev/null 2>&1; then
    echo "錯誤：${settings} 不是合法 JSON，中止安裝（未做任何寫入）。"
    exit 1
fi

dev="${root}/.claude/dev"
mkdir -p "$dev"

created=""
skipped=""

install_file() {
    local src="$1" dest="$2" name="$3"
    if [ -f "$dest" ]; then
        skipped="${skipped} ${name}"
    else
        cp "$src" "$dest"
        created="${created} ${name}"
    fi
}

install_file "${KIT_ROOT}/templates/inbox.md"   "${dev}/inbox.md"   "inbox.md"
# backlog：一筆一檔目錄制（K4 吸收 dfaa 制；舊單檔 backlog.md 模板已退役，
# 存量單檔用 kit/tools/migrate-backlog-to-files.sh 遷移）
mkdir -p "${dev}/backlog"
install_file "${KIT_ROOT}/templates/backlog/INDEX.md" "${dev}/backlog/INDEX.md" "backlog/INDEX.md"

# --- config：互動問 1 題（其餘用預設）
cfg="${dev}/intake.config.yaml"
if [ -f "$cfg" ]; then
    skipped="${skipped} intake.config.yaml"
else
    spec_layer=""
    if [ "$NONINTERACTIVE" = false ]; then
        echo "本專案的規格真理層路徑？（如 docs/rtm/matrix/；無則直接 Enter）"
        printf '> '
        read -r spec_layer || spec_layer=""
    fi
    sed "s|^spec_layer: \"\"|spec_layer: \"${spec_layer}\"|" \
        "${KIT_ROOT}/templates/intake.config.yaml" > "$cfg"
    created="${created} intake.config.yaml"
fi

# --- settings.json merge

if grep -q "${KIT_ROOT}/hooks/" "$settings" 2>/dev/null; then
    skipped="${skipped} settings.json(hooks已安裝)"
else
    cp "$settings" "${settings}.bak-$(date '+%Y%m%d%H%M%S')"
    tmp="$(mktemp)"
    jq --arg k "${KIT_ROOT}/hooks" '
      .hooks //= {}
      | .hooks.UserPromptSubmit //= []
      | .hooks.SessionStart //= []
      | .hooks.Stop //= []
      | .hooks.UserPromptSubmit += [{
          hooks: [{ type: "command", command: ($k + "/capture.sh"), timeout: 5 }]
        }]
      | .hooks.SessionStart += [{
          matcher: "startup|resume|clear|compact",
          hooks: [{ type: "command", command: ($k + "/summary.sh"), timeout: 5 }]
        }]
      | .hooks.SessionStart += [{
          matcher: "startup|resume|clear|compact",
          hooks: [{ type: "command", command: ($k + "/wave-awareness.sh"), timeout: 10 }]
        }]
      | .hooks.Stop += [{
          hooks: [{ type: "command", command: ($k + "/archive.sh"), timeout: 15 }]
        }]
      | .hooks.Stop += [{
          hooks: [{ type: "command", command: ($k + "/no-midwave-questions.sh"), timeout: 10 }]
        }]
    ' "$settings" > "$tmp" && mv "$tmp" "$settings"
    created="${created} settings.json(5個hook)"
fi

# --- .gitignore：kit 執行期產物（鎖檔／快照／衍生 README）不進版控。
# 這三者都是純衍生或純執行期狀態，不含任何原始資料：
#   .inbox.lock/     — capture.sh 的 mkdir 鎖，執行完即釋放
#   .readme-snapshot — gen-readme.sh 用來判斷要不要重生的快照檔
#   README.md        — .claude/dev 的機制索引，100% 由既有檔案掃描產生
# 多 worktree 情境下 README.md 尤其不該進版控：每個 worktree 掃描到的
# 熱區檔案不同，各自產出的內容天生就會分歧，版控只會製造無意義的
# merge 衝突（2026-07-25 自我審查：README.md 在 4 個 checkout 行數各異
# 102/102/102/403，差異純粹來自掃描對象不同，沒有唯一正確版本）。
gitignore="${root}/.gitignore"
[ -f "$gitignore" ] || : > "$gitignore"

gitignore_section_added=false
gitignore_added=""
gitignore_ensure_line() {
    local line="$1"
    grep -qxF "$line" "$gitignore" 2>/dev/null && return 0
    if [ "$gitignore_section_added" != "true" ]; then
        printf '\n# intake kit 執行期檔案（自動產生，非版控內容）\n' >> "$gitignore"
        gitignore_section_added=true
    fi
    printf '%s\n' "$line" >> "$gitignore"
    gitignore_added="${gitignore_added} ${line}"
}

gitignore_ensure_line ".claude/dev/.inbox.lock/"
gitignore_ensure_line ".claude/dev/.readme-snapshot"
gitignore_ensure_line ".claude/dev/README.md"

if [ -n "$gitignore_added" ]; then
    created="${created} .gitignore(intake執行期檔案)"
else
    skipped="${skipped} .gitignore(已含全部條目)"
fi

echo "✅ intake 安裝完成"
[ -n "$created" ] && echo "  新建：${created}"
[ -n "$skipped" ] && echo "  跳過（已存在）：${skipped}"
echo "  hook 於下次 session 開始時生效。"
exit 0
