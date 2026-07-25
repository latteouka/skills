SANDBOX="$(kit_test_sandbox)"
HOOK="$KIT_ROOT/hooks/archive.sh"
DEV="$SANDBOX/.claude/dev"

git -C "$SANDBOX" config user.email t@t.t
git -C "$SANDBOX" config user.name t
cat > "$DEV/intake.config.yaml" <<'EOF'
archive_after_days: 7
EOF

OLD="$(date -v-30d '+%Y-%m-%d' 2>/dev/null || date -d '30 days ago' '+%Y-%m-%d')"
NEW="$(date '+%Y-%m-%d')"

# done 且逾期 → 應被 git rm（dashboard 本身 + ledger + 同 wave_id 的 spec/plan）
cat > "$DEV/wave-old.md" <<EOF
---
wave_id: old
status: done
closed: $OLD
---
# 舊波
做了地圖改版，改用 MapLibre 取代 Leaflet。
EOF

cat > "$DEV/wave-old-ledger.md" <<EOF
# old 的 ledger
決策記錄：選 MapLibre 因授權成本。
EOF

mkdir -p "$SANDBOX/docs/superpowers/specs" "$SANDBOX/docs/superpowers/plans" "$SANDBOX/docs/plans"

cat > "$SANDBOX/docs/superpowers/specs/old-spec.md" <<EOF
---
wave_id: old
---
# old 的 spec
EOF

cat > "$SANDBOX/docs/superpowers/plans/old-plan.md" <<EOF
---
wave_id: old
---
# old 的 plan
EOF

cat > "$SANDBOX/docs/plans/old-notes.md" <<EOF
---
wave_id: old
---
# old 的補充計畫
EOF

# 不相干波的 plan（wave_id 不符）→ 不該被動到
cat > "$SANDBOX/docs/plans/other-notes.md" <<EOF
---
wave_id: other
---
# 不相干的計畫
EOF

# docs/plans 底下完全沒有 frontmatter 的檔 → 不該被動到（kit_fm_get 回空，不比對）
printf '# 沒有 frontmatter 的計畫\n' > "$SANDBOX/docs/plans/freeform.md"

# done 但未逾期 → 不動
cat > "$DEV/wave-fresh.md" <<EOF
---
wave_id: fresh
status: done
closed: $NEW
---
# 新完成的波
EOF

# active → 不動（closed 刻意填「已逾期」的舊日期——如果 status 這道守衛被拿掉，
# 光靠 closed 存在與否擋不住這筆會被誤刪；必須要真的檢查 status 才會安全跳過）
cat > "$DEV/wave-active.md" <<EOF
---
wave_id: active
status: active
opened: $NEW
closed: $OLD
---
# 進行中
EOF

# 無 frontmatter 的舊檔 → 絕不自動動
printf '# 沒有 frontmatter 的舊檔\n' > "$DEV/wave-legacy.md"

git -C "$SANDBOX" add -A >/dev/null 2>&1
git -C "$SANDBOX" commit -qm init >/dev/null 2>&1
PRE_HASH="$(git -C "$SANDBOX" rev-parse HEAD)"

printf '{"hook_event_name":"Stop"}' | (cd "$SANDBOX" && bash "$HOOK") >/dev/null 2>&1

# --- 刪除本體驗證（尚未提交，仍在 working tree 檢查得到）
assert_eq "0" "$([ -f "$DEV/wave-old.md" ] && echo 1 || echo 0)" "逾期 done 的 dashboard 已刪除"
assert_eq "0" "$([ -f "$DEV/wave-old-ledger.md" ] && echo 1 || echo 0)" "對應 ledger 一併刪除"
assert_eq "0" "$([ -f "$SANDBOX/docs/superpowers/specs/old-spec.md" ] && echo 1 || echo 0)" "同 wave_id 的 spec 一併刪除"
assert_eq "0" "$([ -f "$SANDBOX/docs/superpowers/plans/old-plan.md" ] && echo 1 || echo 0)" "同 wave_id 的 plan 一併刪除"
assert_eq "0" "$([ -f "$SANDBOX/docs/plans/old-notes.md" ] && echo 1 || echo 0)" "同 wave_id 的 docs/plans 一併刪除"
assert_eq "1" "$([ -f "$SANDBOX/docs/plans/other-notes.md" ] && echo 1 || echo 0)" "wave_id 不符的 plan 不被刪除"
assert_eq "1" "$([ -f "$SANDBOX/docs/plans/freeform.md" ] && echo 1 || echo 0)" "無 frontmatter 的 plan 不被刪除"
assert_eq "1" "$([ -f "$DEV/wave-fresh.md" ] && echo 1 || echo 0)" "未逾期不動"
assert_eq "1" "$([ -f "$DEV/wave-active.md" ] && echo 1 || echo 0)" "active 不動"
assert_eq "1" "$([ -f "$DEV/wave-legacy.md" ] && echo 1 || echo 0)" "無 frontmatter 舊檔不動"

INDEX_LINE="$(grep '| old |' "$DEV/wave-INDEX.md")"
assert_contains "$INDEX_LINE" "old" "INDEX 有該波記錄"
assert_contains "$INDEX_LINE" "$PRE_HASH" "INDEX 取回指令帶刪除前的 commit hash"
assert_contains "$INDEX_LINE" "wave-old.md" "INDEX 取回指令含 dashboard 路徑"
assert_contains "$INDEX_LINE" "wave-old-ledger.md" "INDEX 取回指令含 ledger 路徑"
assert_contains "$INDEX_LINE" "old-spec.md" "INDEX 取回指令含 spec 路徑"
assert_contains "$INDEX_LINE" "old-plan.md" "INDEX 取回指令含 plan 路徑"
assert_contains "$INDEX_LINE" "old-notes.md" "INDEX 取回指令含 docs/plans 路徑"
assert_not_contains "$INDEX_LINE" "other-notes.md" "INDEX 取回指令不含不相干的 plan"

# --- 冪等（尚未提交）：同一 session 內 Stop 再觸發一次，不應重複寫 INDEX、不應報錯
lines_before_recommit="$(grep -c '| old |' "$DEV/wave-INDEX.md" 2>/dev/null || echo 0)"
printf '{"hook_event_name":"Stop"}' | (cd "$SANDBOX" && bash "$HOOK") >/dev/null 2>&1
rc_rerun_uncommitted=$?
lines_after_recommit="$(grep -c '| old |' "$DEV/wave-INDEX.md" 2>/dev/null || echo 0)"
assert_eq "$lines_before_recommit" "$lines_after_recommit" "未提交狀態下重跑不重複寫 INDEX"
assert_eq "0" "$rc_rerun_uncommitted" "未提交狀態下重跑仍正常結束（檔案已不存在也不報錯）"

# --- 提交刪除，驗證 git log 查得到、取回指令真的能拿回內容
git -C "$SANDBOX" add -A >/dev/null 2>&1
git -C "$SANDBOX" commit -qm "post-hook cleanup" >/dev/null 2>&1

assert_eq "1" "$(git -C "$SANDBOX" log --oneline --diff-filter=D -- .claude/dev/wave-old.md | wc -l | tr -d ' ')" \
    "git log --diff-filter=D 查得到 dashboard 的刪除紀錄"
assert_eq "1" "$(git -C "$SANDBOX" log --oneline --diff-filter=D -- .claude/dev/wave-old-ledger.md | wc -l | tr -d ' ')" \
    "git log --diff-filter=D 查得到 ledger 的刪除紀錄"
assert_eq "1" "$(git -C "$SANDBOX" log --oneline --diff-filter=D -- docs/superpowers/specs/old-spec.md | wc -l | tr -d ' ')" \
    "git log --diff-filter=D 查得到 spec 的刪除紀錄"

dash_cmd="$(printf '%s' "$INDEX_LINE" | grep -o 'git show [0-9a-f]\{7,64\}:\.claude/dev/wave-old\.md' | head -1)"
assert_contains "$dash_cmd" "git show" "能從 INDEX 抽出 dashboard 的取回指令"
dash_content="$(cd "$SANDBOX" && eval "$dash_cmd" 2>/dev/null)"
dash_rc=$?
assert_eq "0" "$dash_rc" "dashboard 取回指令可執行（exit 0）"
assert_contains "$dash_content" "MapLibre" "dashboard 取回指令真的能拿回原內容"

ledger_cmd="$(printf '%s' "$INDEX_LINE" | grep -o 'git show [0-9a-f]\{7,64\}:\.claude/dev/wave-old-ledger\.md' | head -1)"
ledger_content="$(cd "$SANDBOX" && eval "$ledger_cmd" 2>/dev/null)"
assert_contains "$ledger_content" "決策記錄" "ledger 取回指令真的能拿回原內容"

spec_cmd="$(printf '%s' "$INDEX_LINE" | grep -o 'git show [0-9a-f]\{7,64\}:docs/superpowers/specs/old-spec\.md' | head -1)"
spec_content="$(cd "$SANDBOX" && eval "$spec_cmd" 2>/dev/null)"
assert_contains "$spec_content" "old 的 spec" "spec 取回指令真的能拿回原內容"

# --- 冪等（已提交後）：再跑一次仍不重複、不報錯
lines_before_postcommit="$(grep -c '| old |' "$DEV/wave-INDEX.md" 2>/dev/null || echo 0)"
printf '{"hook_event_name":"Stop"}' | (cd "$SANDBOX" && bash "$HOOK") >/dev/null 2>&1
rc_rerun_committed=$?
lines_after_postcommit="$(grep -c '| old |' "$DEV/wave-INDEX.md" 2>/dev/null || echo 0)"
assert_eq "$lines_before_postcommit" "$lines_after_postcommit" "提交後重跑仍不重複寫 INDEX"
assert_eq "0" "$rc_rerun_committed" "提交後重跑正常結束"

rm -rf "$SANDBOX"

# --- Critical 1：畸形 frontmatter（有開頭無結尾）+ 內文含舊日期 → 不刪除
SANDBOX2="$(kit_test_sandbox)"
DEV2="$SANDBOX2/.claude/dev"
git -C "$SANDBOX2" config user.email t@t.t
git -C "$SANDBOX2" config user.name t
cat > "$DEV2/intake.config.yaml" <<'EOF'
archive_after_days: 7
EOF

# 畸形檔案：開頭 --- 但無結尾，內文含「status: done / closed: 舊日期」
cat > "$DEV2/wave-malformed.md" <<EOF
---
wave_id: malformed
status: active
# 內文段落（無結尾 ---）
status: done
closed: 1999-01-01
EOF

git -C "$SANDBOX2" add -A >/dev/null 2>&1
git -C "$SANDBOX2" commit -qm init >/dev/null 2>&1
printf '{"hook_event_name":"Stop"}' | (cd "$SANDBOX2" && bash "$HOOK") >/dev/null 2>&1

assert_eq "1" "$([ -f "$DEV2/wave-malformed.md" ] && echo 1 || echo 0)" "畸形 frontmatter 不被刪除"
rm -rf "$SANDBOX2"

# --- Critical 2：closed 為路徑跳脫 → 不刪除
SANDBOX3="$(kit_test_sandbox)"
DEV3="$SANDBOX3/.claude/dev"
git -C "$SANDBOX3" config user.email t@t.t
git -C "$SANDBOX3" config user.name t
cat > "$DEV3/intake.config.yaml" <<'EOF'
archive_after_days: 7
EOF

cat > "$DEV3/wave-path-escape.md" <<EOF
---
wave_id: escaped
status: done
closed: ../../dangerous
---
# 內文
EOF

git -C "$SANDBOX3" add -A >/dev/null 2>&1
git -C "$SANDBOX3" commit -qm init >/dev/null 2>&1
printf '{"hook_event_name":"Stop"}' | (cd "$SANDBOX3" && bash "$HOOK") >/dev/null 2>&1

assert_eq "1" "$([ -f "$DEV3/wave-path-escape.md" ] && echo 1 || echo 0)" "路徑跳脫不被刪除"
rm -rf "$SANDBOX3"

# --- Critical 3：closed 為非日期格式 → 不刪除
SANDBOX4="$(kit_test_sandbox)"
DEV4="$SANDBOX4/.claude/dev"
git -C "$SANDBOX4" config user.email t@t.t
git -C "$SANDBOX4" config user.name t
cat > "$DEV4/intake.config.yaml" <<'EOF'
archive_after_days: 7
EOF

cat > "$DEV4/wave-baddate.md" <<EOF
---
wave_id: baddate
status: done
closed: not-a-date
---
# 內文
EOF

git -C "$SANDBOX4" add -A >/dev/null 2>&1
git -C "$SANDBOX4" commit -qm init >/dev/null 2>&1
printf '{"hook_event_name":"Stop"}' | (cd "$SANDBOX4" && bash "$HOOK") >/dev/null 2>&1

assert_eq "1" "$([ -f "$DEV4/wave-baddate.md" ] && echo 1 || echo 0)" "非日期格式不被刪除"
rm -rf "$SANDBOX4"

# --- Critical 4（reviewer 回報）：closed 形狀合法但曆法不合法 → 不刪除
# BSD/GNU 的 date 對超出範圍的欄位常常不是直接失敗，而是靜默進位成別的合法
# 日期（如 2026-02-30 → 2026-03-02，exit code 仍是 0）。只驗形狀（四碼-兩碼-
# 兩碼）擋不住這個；字典序比較也擋不住——2026-01-99 這種值字典序常常「早於」
# cutoff，會被誤判逾期而誤刪（reviewer 實測命中的原始案例）。
#
# 四個案例一律用「去年」當年份，確保不管什麼時候跑這個測試，字典序一定早於
# cutoff（年份數字本身就贏了，不必依賴當下月份湊巧落在哪）。
PASTYEAR="$(date -v-1y '+%Y' 2>/dev/null || date -d '1 year ago' '+%Y')"
CURYEAR="$(date '+%Y')"

SANDBOX_CAL="$(kit_test_sandbox)"
DEVCAL="$SANDBOX_CAL/.claude/dev"
git -C "$SANDBOX_CAL" config user.email t@t.t
git -C "$SANDBOX_CAL" config user.name t
cat > "$DEVCAL/intake.config.yaml" <<'EOF'
archive_after_days: 7
EOF

# 案例 1：reviewer 實測命中的原始案例——月份合法（01）、日期不存在（99），字典序早於 cutoff
cat > "$DEVCAL/wave-cal-day99.md" <<EOF
---
wave_id: cal-day99
status: done
closed: ${PASTYEAR}-01-99
---
# 案例 1：reviewer 原始重現
EOF

# 案例 2（取代「只測月份=13」的僥倖版本）：同樣月份合法、日期不存在，但刻意
# 選一個「即使沒有曆法檢查，字典序也一定早於 cutoff」的組合，證明擋下它的是
# 曆法檢查本身、不是字典序運氣——月份不合法（13）的值不管哪一年字典序都
# 「晚於」任何真實月份，用那個測不出防護有沒有真的生效。
cat > "$DEVCAL/wave-cal-day32.md" <<EOF
---
wave_id: cal-day32
status: done
closed: ${PASTYEAR}-01-32
---
# 案例 2：驗證是防護擋下的，不是字典序巧合
EOF

# 附帶對照：2026-13-99 這種「月份不合法」的值本身就只能靠字典序僥倖擋下
# （月份13字典序恆晚於任何真實月份），這裡證明它現在也被曆法檢查擋下，
# 雙重保險而非單靠字典序運氣。
cat > "$DEVCAL/wave-cal-month13.md" <<EOF
---
wave_id: cal-month13
status: done
closed: ${CURYEAR}-13-99
---
# 附帶對照：月份不合法
EOF

# 案例 3：2 月最多 29 天（閏年），30 日不存在
cat > "$DEVCAL/wave-cal-feb30.md" <<EOF
---
wave_id: cal-feb30
status: done
closed: ${PASTYEAR}-02-30
---
# 案例 3：2 月 30 日不存在
EOF

# 案例 4：4 月只有 30 天，31 日不存在
cat > "$DEVCAL/wave-cal-apr31.md" <<EOF
---
wave_id: cal-apr31
status: done
closed: ${PASTYEAR}-04-31
---
# 案例 4：4 月 31 日不存在
EOF

# 正向對照：合法且確實逾期的日期，同一個 sandbox 裡要正常被刪，
# 證明曆法檢查不是「一律不刪」的過度保守版本
cat > "$DEVCAL/wave-cal-valid.md" <<EOF
---
wave_id: cal-valid
status: done
closed: ${PASTYEAR}-01-15
---
# 正向對照：合法日期應正常被刪
EOF

git -C "$SANDBOX_CAL" add -A >/dev/null 2>&1
git -C "$SANDBOX_CAL" commit -qm init >/dev/null 2>&1
printf '{"hook_event_name":"Stop"}' | (cd "$SANDBOX_CAL" && bash "$HOOK") >/dev/null 2>&1

assert_eq "1" "$([ -f "$DEVCAL/wave-cal-day99.md" ] && echo 1 || echo 0)" "曆法不合法（1月99日）不被刪除——reviewer 原始案例"
assert_eq "1" "$([ -f "$DEVCAL/wave-cal-day32.md" ] && echo 1 || echo 0)" "曆法不合法（1月32日）不被刪除——證明是防護生效而非字典序巧合"
assert_eq "1" "$([ -f "$DEVCAL/wave-cal-month13.md" ] && echo 1 || echo 0)" "曆法不合法（13月）不被刪除"
assert_eq "1" "$([ -f "$DEVCAL/wave-cal-feb30.md" ] && echo 1 || echo 0)" "曆法不合法（2月30日）不被刪除"
assert_eq "1" "$([ -f "$DEVCAL/wave-cal-apr31.md" ] && echo 1 || echo 0)" "曆法不合法（4月31日）不被刪除"
assert_eq "0" "$([ -f "$DEVCAL/wave-cal-valid.md" ] && echo 1 || echo 0)" "曆法合法且逾期的日期仍正常被刪（防護不是一律不刪）"

rm -rf "$SANDBOX_CAL"

# --- Important：既有專案殘留 archive_root config key（如 dfaa 舊安裝）→ 不影響行為
# archive_root 已停用，hooks/archive.sh 不再讀它；殘留的 key 應被安靜忽略，不報錯、不影響刪除判斷。
SANDBOX5="$(kit_test_sandbox)"
DEV5="$SANDBOX5/.claude/dev"
git -C "$SANDBOX5" config user.email t@t.t
git -C "$SANDBOX5" config user.name t
cat > "$DEV5/intake.config.yaml" <<'EOF'
archive_after_days: 7
archive_root: .claude/dev/archive
EOF

OLD5="$(date -v-30d '+%Y-%m-%d' 2>/dev/null || date -d '30 days ago' '+%Y-%m-%d')"
cat > "$DEV5/wave-legacy-config.md" <<EOF
---
wave_id: legacy-config
status: done
closed: $OLD5
---
# 殘留 archive_root config 下的正常刪除測試
EOF

git -C "$SANDBOX5" add -A >/dev/null 2>&1
git -C "$SANDBOX5" commit -qm init >/dev/null 2>&1
printf '{"hook_event_name":"Stop"}' | (cd "$SANDBOX5" && bash "$HOOK") >/dev/null 2>&1
rc5=$?

assert_eq "0" "$rc5" "殘留 archive_root key 不導致 hook 出錯"
assert_eq "0" "$([ -f "$DEV5/wave-legacy-config.md" ] && echo 1 || echo 0)" "殘留 archive_root key 不影響正常刪除判斷"
assert_eq "0" "$([ -d "$DEV5/archive" ] && echo 1 || echo 0)" "不再建立任何 archive/ 目錄"
assert_contains "$(cat "$DEV5/wave-INDEX.md")" "legacy-config" "INDEX 仍正確記錄"

rm -rf "$SANDBOX5"

# --- 並發情境下 INDEX 無重複行、無重複刪除
SANDBOX6="$(kit_test_sandbox)"
DEV6="$SANDBOX6/.claude/dev"
git -C "$SANDBOX6" config user.email t@t.t
git -C "$SANDBOX6" config user.name t
cat > "$DEV6/intake.config.yaml" <<'EOF'
archive_after_days: 7
EOF

OLD6="$(date -v-30d '+%Y-%m-%d' 2>/dev/null || date -d '30 days ago' '+%Y-%m-%d')"
for i in 1 2 3; do
  cat > "$DEV6/wave-concurrent-$i.md" <<EOF
---
wave_id: concurrent-$i
status: done
closed: $OLD6
---
# 並發測試 $i
EOF
done

git -C "$SANDBOX6" add -A >/dev/null 2>&1
git -C "$SANDBOX6" commit -qm init >/dev/null 2>&1

# 並發呼叫 5 次（模擬多 session）
for j in 1 2 3 4 5; do
  printf '{"hook_event_name":"Stop"}' | (cd "$SANDBOX6" && bash "$HOOK") >/dev/null 2>&1 &
done
wait

concurrent_1_lines="$(grep -c '| concurrent-1 |' "$DEV6/wave-INDEX.md" 2>/dev/null || echo 0)"
assert_eq "1" "$concurrent_1_lines" "並發下 INDEX 無重複行"
assert_eq "0" "$([ -f "$DEV6/wave-concurrent-1.md" ] && echo 1 || echo 0)" "並發下該刪的檔仍確實被刪"
assert_eq "0" "$([ -f "$DEV6/wave-concurrent-2.md" ] && echo 1 || echo 0)" "並發下第二個檔也確實被刪"
assert_eq "0" "$([ -f "$DEV6/wave-concurrent-3.md" ] && echo 1 || echo 0)" "並發下第三個檔也確實被刪"

rm -rf "$SANDBOX6"

# --- C1（資料損失防護）：三種「刪了救不回」的情境都必須整波跳過，不刪、
# 不寫 INDEX。舊版邏輯 git rm 失敗就 fallback rm -f，三種情境全部靜默毀檔
# （取回指令 git show <hash>:<path> 對從未提交的路徑直接 fatal；有未提交
# 修改的檔案只能拿回舊版，未提交那部分永久消失且無警告）。
OLD_C1="$(date -v-30d '+%Y-%m-%d' 2>/dev/null || date -d '30 days ago' '+%Y-%m-%d')"

# 情境①：gitignore 掉的波檔案（從未 commit 過）
SANDBOX_GI="$(kit_test_sandbox)"
DEV_GI="$SANDBOX_GI/.claude/dev"
git -C "$SANDBOX_GI" config user.email t@t.t
git -C "$SANDBOX_GI" config user.name t
cat > "$DEV_GI/intake.config.yaml" <<'EOF'
archive_after_days: 7
EOF
printf '.claude/dev/wave-gitignored.md\n' > "$SANDBOX_GI/.gitignore"
cat > "$DEV_GI/wave-gitignored.md" <<EOF
---
wave_id: gitignored
status: done
closed: $OLD_C1
---
# 被 gitignore 掉的波（從未 commit 過）
EOF
git -C "$SANDBOX_GI" add -A >/dev/null 2>&1
git -C "$SANDBOX_GI" commit -qm init >/dev/null 2>&1
printf '{"hook_event_name":"Stop"}' | (cd "$SANDBOX_GI" && bash "$HOOK") >/dev/null 2>&1
assert_eq "1" "$([ -f "$DEV_GI/wave-gitignored.md" ] && echo 1 || echo 0)" "C1①：gitignore 掉、從未提交的檔案不被刪除"
assert_eq "0" "$(grep -c '| gitignored |' "$DEV_GI/wave-INDEX.md" 2>/dev/null)" "C1①：不寫入救不回的 INDEX 記錄"
rm -rf "$SANDBOX_GI"

# 情境②：剛建立、還沒 add/commit 的波檔案
SANDBOX_UN="$(kit_test_sandbox)"
DEV_UN="$SANDBOX_UN/.claude/dev"
git -C "$SANDBOX_UN" config user.email t@t.t
git -C "$SANDBOX_UN" config user.name t
cat > "$DEV_UN/intake.config.yaml" <<'EOF'
archive_after_days: 7
EOF
git -C "$SANDBOX_UN" add -A >/dev/null 2>&1
git -C "$SANDBOX_UN" commit -qm init >/dev/null 2>&1
cat > "$DEV_UN/wave-untracked.md" <<EOF
---
wave_id: untracked
status: done
closed: $OLD_C1
---
# 從未 add 過的波
EOF
printf '{"hook_event_name":"Stop"}' | (cd "$SANDBOX_UN" && bash "$HOOK") >/dev/null 2>&1
assert_eq "1" "$([ -f "$DEV_UN/wave-untracked.md" ] && echo 1 || echo 0)" "C1②：從未 commit 過的檔案不被刪除"
assert_eq "0" "$(grep -c '| untracked |' "$DEV_UN/wave-INDEX.md" 2>/dev/null)" "C1②：不寫入救不回的 INDEX 記錄"
rm -rf "$SANDBOX_UN"

# 情境③：已提交過，但有未提交的修改（使用者真正想留住的是修改後的內容）
SANDBOX_DIRTY="$(kit_test_sandbox)"
DEV_DIRTY="$SANDBOX_DIRTY/.claude/dev"
git -C "$SANDBOX_DIRTY" config user.email t@t.t
git -C "$SANDBOX_DIRTY" config user.name t
cat > "$DEV_DIRTY/intake.config.yaml" <<'EOF'
archive_after_days: 7
EOF
cat > "$DEV_DIRTY/wave-dirty.md" <<EOF
---
wave_id: dirty
status: done
closed: $OLD_C1
---
# 舊版內容
EOF
git -C "$SANDBOX_DIRTY" add -A >/dev/null 2>&1
git -C "$SANDBOX_DIRTY" commit -qm init >/dev/null 2>&1
printf '\n未提交的補充內容——這段如果被刪掉就永久消失\n' >> "$DEV_DIRTY/wave-dirty.md"
printf '{"hook_event_name":"Stop"}' | (cd "$SANDBOX_DIRTY" && bash "$HOOK") >/dev/null 2>&1
assert_eq "1" "$([ -f "$DEV_DIRTY/wave-dirty.md" ] && echo 1 || echo 0)" "C1③：有未提交修改的檔案不被刪除"
assert_contains "$(cat "$DEV_DIRTY/wave-dirty.md" 2>/dev/null)" "未提交的補充內容" "C1③：未提交的內容仍完整保留在工作目錄"
assert_eq "0" "$(grep -c '| dirty |' "$DEV_DIRTY/wave-INDEX.md" 2>/dev/null)" "C1③：不寫入只能拿回舊版的 INDEX 記錄"
rm -rf "$SANDBOX_DIRTY"

# --- [NEW] 多 worktree：波檔在 worktree 完成，掃描／刪除仍在 worktree 執行
# （檔案物理上就在那裡），但 wave-INDEX.md 的記錄必須寫進主 checkout——
# 否則每個 worktree 各自累積一份歷史，merge 時互相蓋掉（2026-07-25 自我
# 審查發現：dfaa 主 checkout + 3 worktree 實測 157/157/157/6 行，已分裂）。
WTA_MAIN="$(kit_test_sandbox)"
git -C "$WTA_MAIN" config user.email t@t.t
git -C "$WTA_MAIN" config user.name t
cat > "$WTA_MAIN/.claude/dev/intake.config.yaml" <<'EOF'
archive_after_days: 7
EOF
git -C "$WTA_MAIN" add -A >/dev/null 2>&1
git -C "$WTA_MAIN" commit -qm init >/dev/null 2>&1

mkdir -p "$WTA_MAIN/.claude/worktrees"
git -C "$WTA_MAIN" worktree add -q -b kit-test-archive-wt "$WTA_MAIN/.claude/worktrees/wt-b" >/dev/null 2>&1
WTA_SUB="$WTA_MAIN/.claude/worktrees/wt-b"
WTA_SUB_DEV="$WTA_SUB/.claude/dev"

OLD_WT="$(date -v-30d '+%Y-%m-%d' 2>/dev/null || date -d '30 days ago' '+%Y-%m-%d')"
cat > "$WTA_SUB_DEV/wave-wtdone.md" <<EOF
---
wave_id: wtdone
status: done
closed: $OLD_WT
---
# worktree 完成的波
在 worktree 裡做完的功能。
EOF
git -C "$WTA_SUB" add -A >/dev/null 2>&1
git -C "$WTA_SUB" commit -qm "wave done in worktree" >/dev/null 2>&1

printf '{"hook_event_name":"Stop"}' | (cd "$WTA_SUB" && bash "$HOOK") >/dev/null 2>&1

assert_eq "0" "$([ -f "$WTA_SUB_DEV/wave-wtdone.md" ] && echo 1 || echo 0)" \
    "worktree 內完成的波檔仍從 worktree 刪除（掃描/刪除留在原地）"
assert_contains "$(cat "$WTA_MAIN/.claude/dev/wave-INDEX.md" 2>/dev/null)" "wtdone" \
    "INDEX 記錄寫入主 checkout 的 wave-INDEX.md"
assert_eq "0" "$(grep -c '| wtdone |' "$WTA_SUB_DEV/wave-INDEX.md" 2>/dev/null || echo 0)" \
    "worktree 自己的 wave-INDEX.md 不重複累積這筆（單一歷史落主 checkout）"

git -C "$WTA_MAIN" worktree remove -f "$WTA_MAIN/.claude/worktrees/wt-b" >/dev/null 2>&1
rm -rf "$WTA_MAIN"
