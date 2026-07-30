#!/usr/bin/env bash
# require-requirements-sync.sh — RTM 同步 gate（吸收自 dfaa scripts/hooks/require-requirements-sync.sh，K5）
#
# 政策：行為 diff 未動 <matrix_dir>/ → 擋 commit。code 與 RTM 細節規格
# 不可脫鉤——matrix 是與承辦人對齊的依歸（detail_specs/impl_details/status
# 必須跟上行為現實，不然逐字稿定位與開會對齊全失真）。
#
# 這是提醒閘非正確性閘：只能強制「行為 diff 有動 matrix」，
# 對應關係正確性靠人工審閱。
#
# 逃生口：純重構/樣式/typo 等不改行為的 commit → REQ_SYNC_SKIP="具體理由" git commit ...
# （自報制，誠實使用；理由由 prepare-commit-msg 掛的 append-req-sync-skip-trailer.sh
# 寫入 commit trailer `Req-Sync-Skip: <理由>`，收波稽核可一次掃完所有 skip 理由，
# 濫用會現形）。裸 REQ_SYNC_SKIP=1 或空白不算理由（上游收緊裁定：實查曾有真行為
# 變更誤用裸 1 無留痕）——必須是具體字串。
#
# Merge commit（MERGE_HEAD 存在）自動跳過——內容已在原 branch 審過。
#
# [kit 參數化] 原硬編碼的行為面錨（apps/web/src/server/... 四組）與排除清單
# 改讀專案宣告 <repo>/.claude/kit/kit.yaml（flat-key，kit_decl_get 解析）：
#   reqsync_anchors   空白分隔目錄前綴——命中即視為行為面檔案
#   reqsync_excludes  空白分隔路徑段名——錨內含該段者放行（如 __tests__ migrations）
#   matrix_dir        行為真理層目錄（預設 docs/rtm/matrix）
# reqsync_anchors 未宣告 → SKIP 明示 exit 0（欄位留空＝功能降級必須明示，
# declaration-formats 慣例）。其餘判定邏輯與訊息格式逐位保留上游。
#
# 掛載點：pre-commit（在 lint-staged 之前，純 git 查詢秒級完成）。
# bash 3.2 注意：一律 ${var} 形式。

set -u
set -o pipefail

skip_val="${REQ_SYNC_SKIP:-}"
if [ -n "${skip_val}" ] && [ "${skip_val}" != "1" ]; then
  echo "req-sync: 已跳過（REQ_SYNC_SKIP=\"${skip_val}\"——理由將寫入 commit trailer Req-Sync-Skip）"
  exit 0
fi

git_dir="$(git rev-parse --git-dir 2>/dev/null)" || exit 0
if [ -f "${git_dir}/MERGE_HEAD" ]; then
  exit 0
fi

kit_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${kit_root}/lib/common.sh" 2>/dev/null || {
  echo "req-sync: 找不到 kit/lib/common.sh" >&2; exit 1; }

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
kit_yaml="${repo_root}/.claude/kit/kit.yaml"
matrix_dir="$(kit_decl_get "${kit_yaml}" matrix_dir docs/rtm/matrix)"
matrix_dir="${matrix_dir%/}"
anchors="$(kit_decl_get "${kit_yaml}" reqsync_anchors '')"
excludes="$(kit_decl_get "${kit_yaml}" reqsync_excludes '')"

if [ -z "${anchors}" ]; then
  echo "req-sync: SKIP(reqsync_anchors 未宣告——gate 降級不攔；於 .claude/kit/kit.yaml 宣告後生效)"
  exit 0
fi

# core.quotepath=false：matrix 檔名可能為中文，預設 quotePath 會輸出
# "docs/rtm/matrix/\346..."（帶引號八進位），case pattern 匹配不到（上游實踩）
staged="$(git -c core.quotepath=false diff --cached --name-only 2>/dev/null)"
[ -z "${staged}" ] && exit 0

behavior_hits=""
requirements_touched=0

while IFS= read -r f; do
  [ -z "${f}" ] && continue
  case "${f}" in
    "${matrix_dir}"/*)
      requirements_touched=1
      continue
      ;;
  esac
  anchored=0
  for a in ${anchors}; do
    a="${a%/}"
    case "${f}" in
      "${a}"/*) anchored=1; break ;;
    esac
  done
  [ "${anchored}" -eq 1 ] || continue
  excluded=0
  for x in ${excludes}; do
    case "/${f}" in
      *"/${x}/"*) excluded=1; break ;;
    esac
  done
  [ "${excluded}" -eq 1 ] && continue
  behavior_hits="${behavior_hits}${f}"$'\n'
done <<< "${staged}"

if [ -z "${behavior_hits}" ] || [ "${requirements_touched}" -eq 1 ]; then
  exit 0
fi

echo "❌ rtm-sync: 行為 diff 未同步 ${matrix_dir}/（命中行為面檔案）：" >&2
printf '%s' "${behavior_hits}" | head -5 | sed 's/^/   /' >&2
hit_count="$(printf '%s' "${behavior_hits}" | grep -c . || true)"
if [ "${hit_count}" -gt 5 ]; then
  echo "   …（共 ${hit_count} 檔）" >&2
fi
echo "→ 行為變更必須同 commit 更新 ${matrix_dir}/ 對應款檔（detail_specs/impl_details/status；用 impl_details 反查條目）。" >&2
if [ "${skip_val}" = "1" ]; then
  echo "→ REQ_SYNC_SKIP=1（裸值）已停用——需具體理由，且理由會寫入 commit trailer。" >&2
else
  echo "→ 純重構/樣式/typo 不改行為：" >&2
fi
echo "   REQ_SYNC_SKIP=\"純重構，未改變行為\" git commit -m \"...\"" >&2
exit 1
