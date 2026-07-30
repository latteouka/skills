# 跨 case 隔離探針（與 zz-isolation-canary.sh 成對）。
# 本 case 字典序最前，故意汙染 shell 環境：export 變數、普通變數、函式。
# zz-isolation-canary.sh（字典序最後）驗證這些在其後的 case 一律不可見——
# 若可見＝case 間共享 shell（run.sh 子 shell 隔離失守），canary 會紅。
# 單 case 模式下兩檔各自獨立跑也都會綠（探針只驗自己設定成功）。

export KIT_T8_PROBE_EXPORT="polluted-export"
KIT_T8_PROBE_PLAIN="polluted-plain"
kit_t8_probe_fn() { echo "polluted-fn"; }

assert_eq "polluted-export" "${KIT_T8_PROBE_EXPORT:-}" "探針 export 變數在本 case 內可見"
assert_eq "polluted-plain" "${KIT_T8_PROBE_PLAIN:-}" "探針普通變數在本 case 內可見"
assert_eq "polluted-fn" "$(kit_t8_probe_fn)" "探針函式在本 case 內可呼叫"
