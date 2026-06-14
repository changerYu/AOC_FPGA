# CLAUDE.md — Nexys Video FPGA 手刻 CPU/AXI 專案

本檔是本專案的工作準則。每次開發都先讀它、依它行事；有新決策就回寫進來。

## 1. 專案目標

CPU / AXI 課程作業：**從零用 HDL 手刻**整個系統，目的是練習底層實作。
循序漸進的里程碑：

1. **撥開關控 LED**（先把工具鏈跑通：RTL → XDC → build.tcl → bitstream → 燒錄）
2. 計數器（用 clock enable 控制節奏）
3. 有限狀態機（FSM）
4. UART（收/發）
5. 手刻 AXI 介面（AWVALID/AWREADY、WVALID/WREADY… handshake）
6. 手刻 CPU + 位址解碼 + 周邊整合

### 目前進度 / 下次接續點（HANDOFF）

**里程碑 1：完成並硬體驗證通過（2026-06-14）。** 8 開關對應 8 LED，實機 OK。
- 曾出現「LED1 常亮、LED2/3 恆暗、其餘可控」假象，debug 後確認**軟體全清**
  （XDC 腳位對官方無誤、constraint 全套用、bit 不過期），根因是**隨身碟最上層
  殘留舊專案的 .bit**：USB host 配置只認最上層一個 bit，板子一直讀到舊檔。
  刪掉舊 bit、只留新 `top.bit` 後 8 顆全對。見第 7 節「USB 燒錄坑」。
- `src/top.v`：8 開關直接接 8 LED（`assign led = sw;`），純組合邏輯、無時脈。
- `constraints/nexys_video.xdc`：CFGBVS/CONFIG_VOLTAGE(3.3) + 8 sw（LVCMOS12）
  + 8 led（LVCMOS25）。
- `build.tcl`：專案模式，已成功跑出 `build/top.bit`（0 Error、0 Critical Warning，
  CFGBVS warning 已清；僅剩「無時脈→功耗估計」這個預期 warning）。

**里程碑 1 完成後，專案主軸轉向（2026-06-14 使用者決策）**：
不再走「計數器→FSM→UART→手刻 CPU」的循序里程碑，改為**把既有的 AOC AI 加速器
SoC 移植到 Nexys Video FPGA**。原始碼在 `D:\AOC-final\AOC-vcs-version\`（VCS 已
功能驗證）。詳見第 9 節「AOC EPU 移植」。下次接續點請看第 9 節的 Phase 進度。

**燒錄方式決策**：使用者選擇**全程用 USB 隨身碟燒錄**（已實測可用）。
不要再提議 JTAG / `program.tcl`。註記：USB 燒錄是實體操作，Claude **無法**讀回
燒錄狀態或設計內部值；要回傳設計行為/數值給 Claude debug，靠**里程碑 4 的 UART**
（USB-UART bridge，J13），與燒錄方式無關。

## 2. 硬體

- 開發板：Digilent **Nexys Video**
- FPGA：AMD/Xilinx **Artix-7**，part number `XC7A200T-1SBG484C`
- Vivado part 字串：**`xc7a200tsbg484-1`**
- 板上主時脈：**100 MHz**（接到 pin **R4**，LVCMOS33，差動轉單端後的單端時脈）
- ⚠️ 這是 Artix-7，**沒有 ARM 硬核**（不是 Zynq）。不要用 PS、不要用 Zynq 流程。
- 本機參考手冊：`nexys-video_rm.pdf`

## 3. 工具與環境

- Vivado **2020.2**（已安裝）
  - 安裝路徑：`D:\Xilinx\Vivado\2020.2`（裝在 D 槽，C 槽空間不足）
  - 執行檔：`D:\Xilinx\Vivado\2020.2\bin\vivado.bat`（已加入使用者 PATH）
  - ⚠️ 注意：原始背景寫 2020.1，實際安裝為 **2020.2**（同世代，差異可忽略）。
- OS：**Windows 11 25H2**
- ⚠️ **相容性提醒**：Vivado 2020.2 早於 Windows 11，官方未列為支援平台。
  多數情況可運作，但若遇到 GUI 崩潰、driver/cable 問題、Tcl 行為異常，
  優先懷疑是版本相容性，而非設計錯誤。Linux 端若用很新的 Ubuntu 亦同理。
- 主要工作方式：**CLI / Tcl batch 流程**
  - `vivado -mode batch -source build.tcl`
  - 跑完讀 log（`vivado.log`、`*.rpt`）→ 解讀 warning/error → 修正 → 重跑。
    這個「跑→讀 log→修正」迴路是本專案的核心節奏。

## 4. 硬性開發限制（最重要，違反即不符作業要求）

- ❌ **不使用任何 IP core**：不開 IP Catalog、不產生 `.xci`。
- ❌ **不使用 Block Design / IP Integrator**：不產生 `.bd`。
- ❌ **不使用 Block Memory Generator**：指令/資料 RAM 用適當 coding style
  讓合成器**推斷 (infer)** 成 block RAM。
- ❌ **不使用 Clocking Wizard IP**：需要其他頻率時，優先用 **primitive
  實例化**（如 `MMCME2_BASE`、`PLLE2_BASE`），不開 wizard。
- ❌ **不用計數器除頻產生 gated clock**：需要較慢節奏時，用 **clock enable**
  控制（單一 100 MHz 時脈 + enable 脈衝），不要產生衍生時脈去當 clock 用。
- ✅ **所有 RTL 自己手寫** Verilog/VHDL，在 top module 自行實例化、自行連線。
- ✅ **XDC 自己寫**；可參考 Digilent 官方 Nexys Video master XDC
  （`digilent-xdc` repo）取用需要的腳位，只取用到的、不要整包貼。
- ✅ **澄清**：device primitive（MMCM/PLL、IBUF/OBUF/IBUFDS 等 IO buffer）用
  module **實例化是允許的**，不算 IP。但本作業**能 infer 就 infer**，
  primitive 只在必要時（如真的需要其他頻率）才用，並先跟使用者討論。

## 5. 目錄結構

```
D:\AOC-final\
├── CLAUDE.md            # 本檔
├── .gitignore           # 擋掉 build/ 與 Vivado 暫存
├── build.tcl            # 建置腳本（專案模式）
├── src\                 # 所有 HDL 原始碼 (.v / .sv / .vhd)
├── constraints\         # XDC 約束檔
├── build\              # 建置輸出（.xpr 專案、bitstream、log、報告）— 不進版控
└── nexys-video_rm.pdf   # 板卡參考手冊
```

- 專案路徑保持**純英文、無空格、無中文**（`D:\AOC-final` 符合）。
- 對 git 友善：`src/`、`constraints/`、`build.tcl`、`CLAUDE.md`、`.gitignore`
  進版控；`build/`（含 `.xpr`、`.runs` 等）與 Vivado 暫存皆不進版控，
  全部可由 `build.tcl` 重建。
- git 是**本機**版控，`git init` 即可，**不需要 GitHub**；GitHub 只是選配的
  雲端備份/分享。

## 6. 建置流程（build.tcl 規範）

採 **專案模式 (Project Mode)**：CLI 批次跑完會留下 `.xpr`，可掀開 GUI
視覺化檢視「剛剛 CLI 合成/實作出什麼」（符合使用者需求；波形不需要，
RTL 已在 VCS 驗過）。`build.tcl` 流程：

1. `create_project ... -part xc7a200tsbg484-1`（每次 `-force` 乾淨重建）
2. `add_files` 加入 `src/` 的 HDL 與 `constraints/` 的 XDC
3. `set_property top top` 設定頂層
4. `launch_runs synth_1` → `wait_on_run`（檢查 PROGRESS == 100%）
5. `launch_runs impl_1 -to_step write_bitstream` → `wait_on_run`
6. 輸出 `utilization.rpt`、`timing_summary.rpt`、`top.bit` 到 `build/`

執行：
```powershell
vivado -mode batch -source build.tcl
```

跑完掀開 GUI 檢視：
```powershell
vivado build\aoc_final\aoc_final.xpr
```

⚠️ **坑：重跑 build 前要先關掉 GUI。** `build.tcl` 第一步 `file delete -force`
會砍掉舊專案重建；若 Vivado GUI 正開著該專案，會鎖住 `build\...\impl_1\*.pb`
等檔，導致刪除失敗、build 報 `permission denied`。重跑前先關 GUI。

⚠️ **編碼：工具吃的檔（XDC、build.tcl）一律用英文 ASCII 註解。** Windows 繁中
環境的主控台/編輯器預設 Big5(cp950)，UTF-8 中文會變亂碼。中文只放 CLAUDE.md。

## 7. 燒錄（由使用者執行實體硬體操作）

- 需要實體板卡，**燒錄由使用者本人執行**；Claude 負責把 `build/top.bit` 準備好。
- **決策：全程用 USB 隨身碟燒錄**（已實測可用），不走 JTAG。流程：
  1. 板上跳線 **JP4 → USB/SD**、**JP3 → USB**（JP4 在 JTAG 位置時隨身碟燒不進去）。
  2. 把 `build/top.bit` 複製到隨身碟**最上層** → 插板上 USB Host 口 → 上電。
- ⚠️ **USB 燒錄坑（已踩過）**：USB host 配置**只認最上層一個 `.bit`**。若上層
  殘留舊專案的 bit，板子會讀到舊檔（症狀：部分功能正常、部分恆定不動，像硬體壞）。
  **每次燒錄前先清掉隨身碟上層所有舊 bit，只留當次新的。**
- bitstream 是揮發性的（斷電消失）；燒 QSPI flash 是另一條流程，需要時再談。

## 8. 互動約定

- 使用者**從零開始**，請循序漸進、每步說明「在做什麼、為什麼」。
- 遇到合成/實作的 warning 幫忙解讀（哪些可忽略、哪些要修）。
- 需要使用者親自在 Vivado GUI 操作時（例如掀開 GUI 建立空白專案、
  接上硬體燒錄），給出明確的點擊/輸入步驟。
- 回覆語言：**繁體中文**。

## 9. AOC EPU 移植（FPGA）— 主軸工作

**背景**：`D:\AOC-final\AOC-vcs-version\` 是一顆 VCS 驗證過的 ECG 心律分類 SoC
（RISC-V CPU+FPU、AXI fabric、L1/L2 cache、DMA、ROM/DRAM、WDT + **EPU** Transformer
加速器）。原為 Synopsys DC 跑 TSMC 16nm ASIC 流程。課程官方評分環境是 Ubuntu+
Verilator，**不要求 FPGA**；上板是使用者自訂的硬體挑戰。模型＝TinyArrhythmiaTransformer
（~6643 參數，PoT 無乘法器、ReLU、log-domain softmax/LN、storage-aware UINT8 邊界）。

⚠️ **branch 修正（2026-06-14）**：一開始磁碟上是**載錯的舊 branch**（有 TS1N16 ASIC
巨集、PDCDG pad、外部 ROM/DRAM 的 CHIP）。使用者已換成**正確的 FPGA branch**。以下
全部以正確 branch 為準；任何提到 TS1N16/PDCDG/外部記憶體的舊結論作廢。

**正確 branch 已完成的 FPGA 化（組員做的）**：
- **所有記憶體已 inferred**：`EPU/GLB.sv`=`ram_style="block"` 32K×32、`data_array_wrapper`
  =block、`tag_array_wrapper`=distributed、`ROM_wrapper`=`$readmemh rom0-3.hex`、
  外部 DRAM→`AXI_BRAM_Buffer_wrapper`（包 `SRAM_wrapper` BRAM）。**已無 TS1N16 巨集**。
- **`CHIP.v` 已是 FPGA 頂層**：拿掉 pad 與外部 ROM/DRAM 腳，輸出
  `result_valid` / `result_class[2:0]` / `result_score[7:0]`（class 0=N,1=S,2=V,3=F,4=Q）。
  仍有 4 個輸入時脈+4 reset（cpu/axi/rom/dram）。
- **`src/rtl_fpga_auto.f`**＝FPGA 檔案清單（整顆 SoC），由 `script/gen_fpga_filelist.py` 產。

**EPU 介面（EPU.sv，已讀碼確認）**：`clk`/`rst_n`/`system_start_i` + System SRAM 埠
（`System_A[13:0]`/`DI`/`DO`/`CEB`/`WEB`）+ `busy_o`/`done_o`/`layer_done_o` +
**`result_valid_o`/`result_class_o[2:0]`/`result_score_o[7:0]`（argmax 做在 EPU 內部！）**。
- **GLB 在 EPU 內部**（`GLB u_glb`），有 `glb_preload_mode` mux：高＝System 埠外部預載
  bank0；低＝內部 global_controller 自走。最終 5 個 uint8 logits 寫到 GLB byte `0x3BA00`。
- pipeline（patch_embed→…→head_ecg/rr→logit_add→finish）由 global_controller 自走。

**GLB 記憶體佈局（link.ld + 硬體已交叉確認）**：glb 區 ORIGIN 0x30000 / 128KiB＝32K words。
`__input_glb_word_base=0`、`__weight_glb_word_base=1024`；`decoder.sv BASE_POS_EMBED=15'd1024`
與之吻合。資料在 `sim/fpga/`：`in.dat`=**544 words**（放 word 0+）、`weight.dat`=**3456
words**（放 word 1024+），其餘 0。每行一個 32-bit hex word（見 `txt2bin.py`）。

**⛔ 整顆 SoC 路線的阻擋點**：韌體 **rom0-3.hex 尚未編譯**（`sim/fpga/README_FPGA_
FIRMWARE_CHANGES.md` 自承無 RISC-V 工具鏈、未 rebuild）。沒韌體 ROM＝CPU 不動。

**移植決策（2026-06-14，使用者授權 Claude 判斷）**：**走獨立 EPU + 靜態 GLB 影像**。
不靠 ROM/CPU/韌體/DMA、不需 RISC-V 工具鏈、不需模擬器。把 `in.dat`(@word0)+
`weight.dat`(@word1024)+補 0 靜態組成 32K-word `glb_init.hex`，用 **BRAM `$readmemh`
初始化** GLB（等同 DMA 預載完成的狀態），再拉 `system_start_i`，等 `result_valid_o`。

**上板驗收目標（golden）**：`sim/fpga/golden.hex`=`25113D67` → 5 logits LE＝
[0x67,0x3D,0x11,0x25,0x00]＝[103,61,17,37,0] → **argmax=class 0 (N)，score=0x67=103**。
板上 LED 應顯示 `result_class=0`、`result_score=103`。

**Phase A 步驟**：① 生成 `glb_init.hex`（in@0 / weight@1024 / 其餘0，32768 行）。
② 改 `GLB.sv` 加 `$readmemh` 參數做 BRAM 初始化（沿用同模組）。③ 新板級頂層：單一
100MHz（必要時降頻收斂）+ reset 同步，直接實例化 `EPU`（System 埠閒置、`glb_preload_mode`
保持 0）+ start FSM + result 鎖存。④ 寫 Nexys Video XDC（clk R4 / reset btn / LED）。
⑤ build.tcl 只收 `src/EPU/*.sv`+GLB+板級頂層，synth→impl→bit→USB 燒。LED 比對 golden。
**Phase B（之後）**：補 RISC-V 工具鏈編韌體 → 上整顆 CHIP（CPU 自動載 GLB、啟 EPU）。

**Phase A 產出（全在 `D:\AOC-final\epu_fpga\`，與里程碑1 的 LED 流程分開）**：
- `gen_glb_init.py` → `glb_init.hex`（32768 字，in@0/weight@1024/補0）。
- `rtl/GLB.sv`：FPGA 覆蓋，`$readmemh` 用**絕對路徑** `D:/AOC-final/epu_fpga/glb_init.hex`
  初始化 BRAM（裸檔名 Vivado 合成找不到會「靜默忽略→BRAM 全0→結果全錯」，已踩過）。
- `rtl/epu_top.sv`：板級頂層（reset 同步 + start FSM + result→LED mux，sw[1:0] 選顯示）。
- `constraints/epu_nexys_video.xdc`：clk R4 / rst=BTNC(B22) / sw[1:0] / led[7:0]。
- `build_epu.tcl`：只收 `src/EPU/*.sv`（去 EPU_Wrapper、去原 GLB）+ 上述；define.svh 設
  `is_global_include`。執行：`cd epu_fpga; vivado -mode batch -source build_epu.tcl`。

**進度（2026-06-14）**：**Phase A build 通過，待硬體驗證。** `build/epu_top.bit` 已產出，
**100MHz 時序達標**（WNS>0，不需降頻）、`glb_init.hex` 確認載入 BRAM、0 error/0 critical、
資源寬裕（LUT 18.7% / BRAM 32 顆 8.8% / DSP 11 顆 1.5%）。157 warnings 均良性
（unconnected port 等；latch/multi-driver/result 截斷皆無）。
- **上板驗收 golden**：sw=00→LED=score 應 `0x67`(103,01100111)；sw=01→LED7=valid 應亮、
  LED2:0=class 應 `000`(N)；sw=10→狀態旗標；sw=11→心跳（確認時脈活著）。
- **✅ Phase A 硬體驗證通過（2026-06-14）**：USB 燒 `epu_top.bit` 上板，sw=00 LED 顯示
  score=0x67(103)、sw=01 class=000(N)+valid 亮、sw=10 valid=1/busy=0、sw=11 心跳正常。
  **EPU 端到端在 Nexys Video 上跑通，輸出與 VCS golden 逐位元相符。** done 為脈衝（穩態
  看不到屬正常，靠 result_valid 鎖存）。
**git 版控（2026-06-14）**：`D:\AOC-final` 已 `git init`，known-good 基準 commit `4ed14f7`，
推到 GitHub `https://github.com/changerYu/AOC_FPGA`（branch `main`）。`.gitignore` 擋掉
`aoc-vcs-version/`(482MB 外部源碼)、`build/`、`.claude/`、PDF。能跑的 bit 永久保留於
`epu_fpga/release/epu_top_v1.bit`。**往後在分支實驗，main 維持 known-good。**

**目標架構（使用者 2026-06-14 定的最終方向，強化 demo 暫緩）**：完整即時系統 ——
`PC →(USB/WiFi) ESP32 → UART → [FPGA UART RX] → Buffer Slave(BRAM)`，**按鈕觸發**後
`CPU →AXI/DMA→ EPU GLB → 分類 → result`。ROM 只放韌體（in.dat 不再進 ROM，改執行期
經 UART 進 buffer）。對應現有積木：buffer slave ≈ 現成 `AXI_BRAM_Buffer_wrapper.sv`；
CPU/AXI/DMA/EPU 都在；**唯一要新寫的是 UART RX→buffer**（呼應原里程碑4 UART）。
- 設計決策（待定）：UART 進 buffer 建議走**雙埠 BRAM**（UART 寫一埠、CPU 經 AXI 讀另一埠，
  UART 不必懂 AXI）；UART 框架需「整筆 544 字=2176B 到齊」判斷；ESP32 非必要（板上
  FT2232 USB-UART 可直接用，ESP32 只在要無線/感測前端時才加）；結果可同條 UART 加 TX 回傳。
- **建議分階段**（每步可獨立上板）：
  - **B0（前提）**：整顆 CHIP 先在 FPGA build 起來 → 需 rom*.hex 韌體（缺 RISC-V 工具鏈，
    請組員 Docker `make` 給 hex，或本機裝 toolchain）。
  - **B1（可先做、免韌體）**：獨立 EPU 上加 UART RX→寫 GLB→按鈕啟動，把 V1 的靜態
    `$readmemh` 換成「UART 即時餵 + 按鈕跑」，先驗證整條 UART→EPU 資料路。
  - **B2**：接上 buffer slave + CPU/DMA，組成完整流程。
- **進度（2026-06-14）**：**B1 已選定並 build 通過，待硬體驗證。** 分支 `feature/uart-epu`。
  新增（`epu_fpga/`）：`rtl/uart_rx.sv`（8N1@115200）、`rtl/epu_uart_top.sv`（框架解析
  AA55+2176B payload+XOR → loader 經 EPU System 埠寫 GLB 0..543 → BTNC 啟動）、
  `constraints/epu_uart_nexys_video.xdc`（UART RX=JA1/AB22、TX=JA7/Y21、rst=BTND、
  start=BTNC）、`build_epu_uart.tcl` → `build/epu_uart_top.bit`（0 err/0 crit、時序達標）。
  ESP32（`ESP32_Arduino_UART/esp32_epu_uart/`）：`.ino` 用框架送寫死 golden 樣本 +
  `golden_sample.h`（544 字，由 `gen_golden_sample.py` 從 glb_init.hex 產）。
  接線：ESP32 GPIO17→JA1(AB22)、GPIO16→JA7(Y21)、GND→JA pin5/11。權重維持烤死，
  只有輸入經 UART 進來；不送 UART 直接按 BTNC 會跑烤進去的 golden（等同 V1 sanity）。
  驗收：UART 送幀→按 BTNC→sw=00 LED=0x67、sw=01 class=000+valid；sw=10 LED4=data_ready
  /LED5=uart_err。
- **✅ B1 硬體驗證通過（2026-06-14）**：正確順序 = **reset(BTND) → ESP32 送幀 → 等
  data_ready(LED4 亮，LED5 uart_err 暗) → 按 BTNC**。實測 data_ready 亮、uart_err 暗、
  sw=00=0x67 → **ESP32→UART→uart_rx→框架解析→寫 GLB→EPU 算出 class N 整條打通**。
  ⚠️ UX 坑：先按 BTNC 會從 F_SYNC0 跑「烤進去的 golden」並鎖死在 F_RUN，擋掉 UART 路；
  必須先 reset。ESP32 sketch 確認送出 2179 bytes/checksum 0x67。
- **🔒 B1 鐵證測試通過（2026-06-14）**：診斷版 `build/epu_uart_top_zeroinput.bit`
  （輸入區烤成 0、權重保留；source 見 `rtl_zeroinput/GLB.sv`、`glb_init_zeroinput.hex`、
  `build_epu_uart_zeroinput.tcl`、`gen_glb_init.py --zero-input`）。實測：
  **無 UART → class S(1)/score 0x6B(107)；有 UART → class N(0)/score 0x67(103)**。
  結果隨 UART 輸入改變 → 確證板上結果來自 UART 串流資料，非烤死 fallback。
  ⚠️ UX 坑保留：先按 BTNC 會跑 fallback 並鎖死 F_RUN，必須 reset→送 UART→等 data_ready→start。
