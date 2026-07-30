# 跨 case 隔離 canary（與 aa-isolation-probe.sh 成對；本檔須維持字典序最後）。
# aa-isolation-probe.sh 在整套最前面故意 export 變數、設普通變數、定義函式；
# 走到本 case 時三者必須全部不可見——run.sh 全套模式每個 case 跑在子 shell，
# 任何殘留可見＝隔離失守（舊 harness 用共享 shell source，本 case 必紅）。

assert_eq "" "${KIT_T8_PROBE_EXPORT:-}" "前案 export 變數不得殘留到本 case"
assert_eq "" "${KIT_T8_PROBE_PLAIN:-}" "前案普通變數不得殘留到本 case"

zz_fn_state="absent"
if type kit_t8_probe_fn >/dev/null 2>&1; then zz_fn_state="present"; fi
assert_eq "absent" "$zz_fn_state" "前案函式不得殘留到本 case"
