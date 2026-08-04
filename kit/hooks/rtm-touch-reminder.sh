#!/usr/bin/env bash
# rtm-touch-reminder.sh — Claude Code PostToolUse hook（matcher: Write|Edit）。K5 新作（讀側方向 1）。
#
# 職責：寫入檔命中 .claude/kit/rtm-index.tsv（rtm-check --emit-index 產物，
# 檔案→RTM 條目反查表）→ 注入提醒「此檔屬條目 X，確認行為變更已對照/回寫」。
# 純 bash grep/awk 毫秒級——tsx/node 不進熱路徑；index 重生歸 rtm-session-start.sh。
#
# exit 語意（Fable 諮詢點 1 裁定）：命中、與「首次」index 缺失/過期提醒 →
# exit 2 傳訊（PostToolUse exit 2 只把 stderr 餵給 Claude，不 block）；
# 其後同 session 靜默 exit 0（不 nag）。
#
# 去重：seen 檔帶 session_id 後綴（stdin JSON .session_id），存
# .claude/kit/.rtm-seen/<session_id>；粒度＝(session, 檔案, 條目)。
# GC 歸 rtm-session-start.sh（mtime >7 天，不清現役）。
#
# 提醒命中 log：append .claude/dev/.rtm-reminder-log（TSV：時間、session、
# 檔案、條目、kind=hit|stale）——誤報率帳的數據基礎。
#
# 比對：file_path 剝 ${CLAUDE_PROJECT_DIR}/ 前綴後與 index 第 1 欄精確比對；
# 剝不動（前綴不符）→ fallback 尾綴比對（file_path 以 "/<index 欄1>" 結尾）。
#
# 過期偵測：index 首行 matrix_hash=sha256:<hex> vs 現算——matrix_dir 內 *.yaml
# 以 LC_ALL=C 排序串接 shasum -a 256，與引擎 TS 側同公式（兩側同值由
# tests/cases/rtm-check.sh 看守）。公式刻意內聯而非進 lib/common.sh
# （K5 commit 白名單不含 common.sh；K6 可整併），改動時與
# rtm-session-start.sh 內同名函式同步。
#
# fail-open：無 jq／stdin 異常／找不到 repo 根／matrix_dir 不存在（非 rtm
# 專案）→ exit 0。pass 靜默。bash 3.2：一律 ${var} 形式。

set -u

command -v jq >/dev/null 2>&1 || exit 0
input="$(cat 2>/dev/null)" || exit 0
[ -n "${input}" ] || exit 0

file_path="$(printf '%s' "${input}" | jq -r '.tool_input.file_path // empty' 2>/dev/null)"
[ -z "${file_path}" ] && exit 0
session_id="$(printf '%s' "${input}" | jq -r '.session_id // empty' 2>/dev/null)"
[ -n "${session_id}" ] || session_id="unknown"

project_dir="${CLAUDE_PROJECT_DIR:-}"
[ -n "${project_dir}" ] || project_dir="$(git rev-parse --show-toplevel 2>/dev/null)"
[ -n "${project_dir}" ] || exit 0

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${script_dir}/../lib/common.sh" 2>/dev/null || exit 0

matrix_dir="$(kit_decl_get "${project_dir}/.claude/kit/kit.yaml" matrix_dir docs/rtm/matrix)"
matrix_dir="${matrix_dir%/}"
matrix_abs="${project_dir}/${matrix_dir}"
[ -d "${matrix_abs}" ] || exit 0

index="${project_dir}/.claude/kit/rtm-index.tsv"
seen_dir="${project_dir}/.claude/kit/.rtm-seen"
seen="${seen_dir}/${session_id}"
log_file="${project_dir}/.claude/dev/.rtm-reminder-log"

# log_append <kind> <條目（無則 -）>
log_append() {
  mkdir -p "${project_dir}/.claude/dev" 2>/dev/null || return 0
  printf '%s\t%s\t%s\t%s\t%s\n' \
    "$(date '+%Y-%m-%dT%H:%M:%S')" "${session_id}" "${file_path}" "$2" "$1" \
    >> "${log_file}" 2>/dev/null || true
}

# 與 rtm-session-start.sh／引擎 --emit-index 同公式（見頭註）
matrix_hash_now() {
  (cd "${matrix_abs}" 2>/dev/null \
    && LC_ALL=C find . -maxdepth 1 -name '*.yaml' 2>/dev/null | LC_ALL=C sort \
    | while IFS= read -r mf; do cat "${mf}"; done) \
    | shasum -a 256 | awk '{print $1}'
}

stale=""
if [ ! -f "${index}" ]; then
  stale="rtm-index 缺失"
else
  header_hash="$(head -1 "${index}" | sed -n 's/.*matrix_hash=sha256:\([0-9a-f]*\).*/\1/p')"
  if [ -z "${header_hash}" ] || [ "${header_hash}" != "$(matrix_hash_now)" ]; then
    stale="rtm-index 過期（matrix 已變動）"
  fi
fi

if [ -n "${stale}" ]; then
  if [ -f "${seen}" ] && grep -qxF "stale" "${seen}" 2>/dev/null; then
    exit 0
  fi
  mkdir -p "${seen_dir}" 2>/dev/null || exit 0
  printf 'stale\n' >> "${seen}" 2>/dev/null || true
  log_append stale -
  echo "rtm-reminder: ${stale}——下個 session 開啟時自動重生（或手動跑 rtm-check --emit-index）；此檔若屬 RTM 條目請自行對照 ${matrix_dir}/ 回寫" >&2
  exit 2
fi

rel="${file_path#"${project_dir}"/}"
if [ "${rel}" != "${file_path}" ]; then
  hits="$(awk -F'\t' -v p="${rel}" '!/^#/ && NF >= 2 && $1 == p { print $2 }' "${index}" 2>/dev/null | sort -u)"
else
  # 前綴剝不動 → 尾綴比對（不用 regex，避免路徑特殊字元誤匹配）
  hits="$(awk -F'\t' -v fp="${file_path}" '!/^#/ && NF >= 2 {
      if (fp == $1) { print $2; next }
      suf = "/" $1
      if (length(fp) > length(suf) && substr(fp, length(fp) - length(suf) + 1) == suf) print $2
    }' "${index}" 2>/dev/null | sort -u)"
fi
[ -n "${hits}" ] || exit 0

new_ids=""
while IFS= read -r id; do
  [ -z "${id}" ] && continue
  if [ -f "${seen}" ] && grep -qxF "hit:${rel}:${id}" "${seen}" 2>/dev/null; then
    continue
  fi
  new_ids="${new_ids}${id} "
done <<< "${hits}"
new_ids="${new_ids% }"
[ -n "${new_ids}" ] || exit 0

mkdir -p "${seen_dir}" 2>/dev/null || exit 0
for id in ${new_ids}; do
  printf 'hit:%s:%s\n' "${rel}" "${id}" >> "${seen}" 2>/dev/null || true
done
log_append hit "${new_ids}"
echo "rtm-reminder: ${rel} 屬 RTM 條目 ${new_ids}——若本次是行為變更，請對照 ${matrix_dir}/ 對應條目回寫（detail_specs/impl_details/status）。回寫守則：①先站在被驗收者角度檢視條目現況——欄位已偏離現狀就整段重寫，不要只 append 疊行；②detail_specs＝給承辦人的正式文書：零程式識別字（函式/元件名、issue/B-編號不進），技術名詞轉業務用語（如 party→關係人、Dialog→對話框），SSO/API/IMEI/GPS 等常見縮寫與（2碼）類格式說明可留；impl_details 才放 code 定位。純重構/樣式可忽略本提醒" >&2
exit 2
