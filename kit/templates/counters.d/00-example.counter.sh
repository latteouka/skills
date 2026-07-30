#!/usr/bin/env bash
# counters.d 宣告契約範例（ratchet counter；引擎＝kit/engines/ratchet.sh）
#
# 檔名即 counter 名：<name>.counter.sh → counter 名 <name>，必須與專案 baseline
# JSON 的 .counters.<name> 鍵一一對應（引擎雙向核對：有鍵無檔、有檔無鍵皆
# fail-closed）。本範例檔名 00-example.counter.sh → counter 名「00-example」——
# 真實 counter 通常不帶 NN- 前綴（載入順序不影響 ratchet 語意）；NN- 前綴保留給
# 同目錄的共用 helper 檔 NN-*.lib.sh（先於全部 counter 檔按字典序載入，
# 不參與名稱推導與雙向核對）。
#
# 引擎消費契約：
#   - 必須定義 count_<name>()（name 的 - 轉 _）：stdout 輸出**單一非負整數**，
#     不多印任何雜訊（診斷訊息走 stderr）；無法可信計數時 return 1——引擎
#     fail-closed：compare／--tighten 立即紅、--report 印 ERROR 行。
#     「數不出來」絕不能輸出 0：假 0 比真失敗危險（依賴未裝、config 解析失敗、
#     binary 路徑錯是假 0 三大源，先驗工具存在與 exit code 再信計數）。
#   - 本檔以 source 載入引擎行程：**禁 set -e／禁 exit**（會殺掉整個引擎），
#     失敗一律 return 1；頂層只定義函式、不執行任何動作；不得覆寫
#     PROJECT_ROOT／BASELINE_FILE／ratchet_ 前綴的引擎內部變數。
#   - 保證可用的環境變數（僅此兩個，其餘自備）：
#       PROJECT_ROOT   受檢 repo 根的絕對路徑
#       BASELINE_FILE  baseline JSON 絕對路徑（kit.yaml baseline_file 宣告解析後）
#     另：RATCHET_FULL=1 表示全量模式（降載型 counter 可讀它決定掃描範圍）。
#   - 選配 inputs_<name>()：stdout 一行一 git pathspec（repo-root 相對）。
#     定義後 compare 模式在「宣告的 pathspec 相對 origin/<base_branch> 無變更」
#     時 skip 本 counter、沿用 baseline；未定義＝永不 skip（保守）。
#     --tighten／--report 一律全跑，不看 inputs_。
#   - 計數值須可重現：同一 commit 上重跑兩次必須得到同一個數字（依賴外部
#     浮動源時把浮動源釘死或 fail-closed，不輸出長得像正常值的無意義數字）。

# 範例：數 repo 內登記在案的 *.todo 債檔數
count_00_example() {
  local n
  n="$(find "${PROJECT_ROOT}" -maxdepth 2 -type f -name '*.todo' 2>/dev/null | wc -l | tr -d ' ')"
  case "${n}" in
    ''|*[!0-9]*) return 1 ;;
  esac
  printf '%s\n' "${n}"
}

# 範例（選配）：只有 *.todo 相關變更時才需要重數，其餘 push 沿用 baseline
inputs_00_example() {
  printf '%s\n' '*.todo'
}
