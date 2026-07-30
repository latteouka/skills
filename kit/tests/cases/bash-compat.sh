# bash-compat.sh — bash 3.2 相容禁用構文全庫掃描（K2 Fable 建議機器化）
#
# macOS 內建 bash 3.2：declare -A / mapfile / readarray / ${var,,} / ${var^^} /
# local -n 皆不存在。kit 全部 .sh 必須 0 命中（註解行除外——掃描剝註解後比對）。

BC_HITS=""
for f in $(cd "$KIT_ROOT" && find engines gates tools hooks scripts lib installers -name '*.sh' -type f 2>/dev/null; ls "$KIT_ROOT"/tests/cases/*.sh 2>/dev/null | sed "s|$KIT_ROOT/||"); do
    # 自身排除（掃描 pattern 字串會自我命中）
    case "$f" in */bash-compat.sh|tests/cases/bash-compat.sh) continue ;; esac
    # 剝註解（行首空白後 # 開頭的整行）再掃
    hits="$(sed 's/^[[:space:]]*#.*$//' "$KIT_ROOT/${f#"$KIT_ROOT"/}" 2>/dev/null | grep -nE 'declare -A|mapfile|readarray|\$\{[A-Za-z_][A-Za-z0-9_]*(,,|\^\^)\}|local -n' | head -3)"
    [ -n "$hits" ] && BC_HITS="${BC_HITS}${f}: ${hits}
"
done
assert_eq "" "$BC_HITS" "bash 3.2 禁用構文全庫 0 命中（違規：${BC_HITS:-無}）"
