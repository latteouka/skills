<!-- kit:rtm:begin -->
<!-- 此段由 kit --rtm 安裝（installers/modules/rtm.sh，marker 冪等）。
     安裝時把 {{MATRIX_DIR}} 代換為 kit.yaml 的 matrix_dir（如 docs/rtm/matrix/）。 -->

**🎯 行為定位協議（CRITICAL）**：使用者以口語/逐字稿提到任何功能行為時，**第一個動作＝`grep -r "關鍵詞" {{MATRIX_DIR}}`** 找到對應條目 → 讀該條 `detail_specs`（現況行為）＋`impl_details`（要動哪些檔）→ 才開始讀 code。不准直接全庫搜尋摸索——matrix 就是為了讓定位變 O(1) 而建的。改完行為必須同 commit 更新該條目（pre-commit require-requirements-sync gate 會擋，但主動做而不是被 gate 教育）。

<!-- kit:rtm:end -->
