#!/usr/bin/env bash
# modules/ctl.sh — portfolio-ctl 能力宣告安裝模組。
# 冪等：kit.yaml 缺 ctl_* key 才補（預設全保守）；重跑 diff 零。
#
# 安裝內容：
#   1. kit.yaml scaffold（缺檔才建）＋ ctl_close / ctl_dispatch_auto / ctl_profile
#      三鍵（缺哪補哪，預設 report-only / 0 / dev——最保守）＋ modules 登記
#   2. 輸出後續人工步驟指引：registry 註冊（**刻意不自動**——registry 是授權
#      上限、安裝器/agent 不得自我授權，見 control-contract.md §5）＋ push 提醒
#      （supervisor 只從 origin/main 讀能力，沒 push＝fail closed report-only）
#
# 消費者：portfolio supervisor（~/projects/dotfiles/portfolio-ctl/）。
# 合約 SSOT：~/projects/dotfiles/docs/portfolio-ctl/control-contract.md
# bash 3.2 相容；一律 ${var} 形式（AGENTS.md Shell 鐵則 8）。

set -u

MODULE_DIR="$(cd "$(dirname "$0")" && pwd)"
KIT_ROOT="$(cd "${MODULE_DIR}/../.." && pwd)"
. "${KIT_ROOT}/lib/common.sh" 2>/dev/null || { echo "找不到 lib/common.sh"; exit 1; }
. "${MODULE_DIR}/_shared.sh"  2>/dev/null || { echo "找不到 modules/_shared.sh"; exit 1; }

root="$(kit_repo_root)"
if [ -z "${root}" ]; then echo "錯誤：不在 git repo 內，無法安裝。"; exit 1; fi

kit_module_begin

kit_module_ensure_kit_yaml "${root}" "${KIT_ROOT}"
kit_module_decl_key "${root}" ctl_close "report-only"
kit_module_decl_key "${root}" ctl_dispatch_auto "0"
kit_module_decl_key "${root}" ctl_profile "dev"
kit_module_register "${root}" ctl

kit_module_report "ctl"
proj="$(basename "${root}")"
cat <<EOF
  後續人工步驟（缺一不可）：
  1. commit + push kit.yaml 到 origin/main——supervisor 只讀 trusted ref，
     沒 push＝一律 fail closed report-only。
  2. registry 註冊（人工，防自我授權）：編輯
     ~/projects/dotfiles/claude/portfolio-registry.json 的 projects 加：
       "${proj}": { "path": "${root}", "profile": "dev", "patrol": true,
         "caps": { "ctl_close": "report-only", "ctl_dispatch_auto": "0" },
         "adapters": { "backlog_dir": ".claude/dev/backlog",
                       "dispatch_status": "ready",
                       "worktree_glob": ".claude/worktrees/wave-*",
                       "base_branch": "main" } }
     並 commit dotfiles。有效權限＝kit.yaml ∩ registry 取嚴。
  3. 要讓 supervisor 能收波：registry adapters 補 gate_cmd（專案的收尾檢查指令）。
  4. 要開自動派發：兩側 ctl_dispatch_auto 都設 "1"＋registry 補 dispatch_cmd 模板
     ＋backlog 項掛 prompt:（prompt 檔必須已 push 上 origin/main 才會被派）。
EOF
exit 0
