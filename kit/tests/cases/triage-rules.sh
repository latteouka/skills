TRIAGE_RULES="$(cat "$KIT_ROOT/references/triage-rules.md")"

assert_contains "$TRIAGE_RULES" '`touches`' "triage 規則定義 touches 欄"
assert_contains "$TRIAGE_RULES" '`unknown:<具體原因>`' "triage 規則定義未知 touches 標記"
assert_contains "$TRIAGE_RULES" "exact path" "triage 規則要求 exact path"
assert_contains "$TRIAGE_RULES" "glob" "triage 規則允許 glob"
assert_contains "$TRIAGE_RULES" "交集預警" "triage 規則要求 wave batch 交集預警"
assert_contains "$TRIAGE_RULES" "不得排進同一波或並行波" "確定交集必須阻止並行"
assert_contains "$TRIAGE_RULES" "視為與所有項目交集未明" "未知 touches 必須 fail-safe 預警"
