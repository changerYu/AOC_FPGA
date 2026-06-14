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

> **★ 最新狀態（2026-06-14，使用者暫停休息）★**
> AI 加速器移植主軸進行中（見第 9 節）。已完成且**硬體驗證**：
> **V1**（獨立 EPU 烤死樣本→golden）、**B1**（ESP32→UART→EPU 真實串流分類）、
> **A**（鐵證：結果隨 UART 輸入改變，無→S/0x6B、有→N/0x67）。全部 commit 並 push 上
> GitHub `https://github.com/changerYu/AOC_FPGA`（main = known-good），能跑的 bit 在
> `epu_fpga/release/`。
> **★ B0 進度更新（2026-06-14 晚）★**：RISC-V 工具鏈已裝（WSL2 Ubuntu-24.04），
> `rom0-3.hex` 編出（阻擋點解除）。**整顆 SoC（CHIP）已成功 build 並時序收斂**：
> cpu_clk=100MHz / axi-rom-dram=50MHz（MMCM 雙時脈 + async clock groups），
> WNS +0.089ns、0 critical warning、ROM hex 確認載入。bit 在
> `chip_fpga/release/chip_top_b0.bit`。**✅ B0 上板硬體驗證通過（2026-06-14 晚）**：
> sw=00→0x67(103)、sw=01→class 000(N)+valid、sw=10→LED0~2 全亮(valid+rst_done+locked)、
> sw=11→心跳。整顆手刻 SoC 自走跑通、與 VCS golden 逐位元相符。
> **✅ 模式1 M1a 上板驗證通過（2026-06-14 晚）**：韌體改走 ROM→buffer(0x2000_0000)→
> (main.c DMA)→GLB(0x0003_0000)→EPU，sw=00=0x67(N) 證明 CPU→DMA→buffer→GLB 資料路打通
> （搬失敗會是 0x6B）。bit=`chip_fpga/release/chip_top_m1a.bit`，韌體源碼納入
> `chip_fpga/firmware/`。**✅ M1b 上板驗證通過（2026-06-15）**：改用 **CPU reset 當觸發**
> （使用者決策，取代按鈕中斷——BRAM 內容不被 reset 清掉，故 buffer 資料天生存活）。
> buffer 改成獨立 BRAM（`SRAM_wrapper_buf` `$readmemh buf_init.hex` 預載），boot 不再載
> buffer，main DMA buffer→GLB→EPU。sw=00=0x67 證明解耦 buffer 路徑通。
> bit=`chip_fpga/release/chip_top_m1b.bit`。**⚠️ 設計約束（使用者強調）：資料 buffer 必須
> 永遠在 BRAM、不可改放暫存器**（reset-觸發仰賴 BRAM 存活）。**下次接續＝M1c**：UART RX
> 寫 buffer 第二埠（true dual-port BRAM，資料留 BRAM）→ 送 UART 新資料→按 reset→分類新資料
> （鐵證）。細節見第 9 節 9.Z。
> 其他可選路線：C1（PC 串流多類別 live demo，免韌體，PC 端 `pip install wfdb scipy`）。
> 進 EPU 細節看第 9 節。以下里程碑 1 與轉向背景為歷史記錄。

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

**✅ 阻擋點已解除（2026-06-14）**：原本「韌體 rom0-3.hex 尚未編譯」（缺 RISC-V 工具鏈）
的阻擋已排除。WSL2 Ubuntu-24.04 裝好 `gcc-riscv64-unknown-elf 13.2.0`+`make`+`python3`，
`cd AOC-vcs-version/hardware/sim/fpga && make` **成功編出 `rom0~3.hex`**（各 13375B，4 lane，
`ROM_wrapper` `$readmemh` 格式）。Claude 經 `wsl bash -c` 從 Windows 驅動，hex 直接落
`/mnt/d/...`。注意：這版是**現有 ROM 流程**韌體（in.dat 烤在 ROM）；給 B0 直接可用，模式1
再改 boot.c/main.c。詳見 9.X 節資料路徑與工具鏈說明。

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

### 9.X 整顆 SoC 資料路徑 & 位址 Map（2026-06-14 讀碼整理，為 B0/B2/雙模式做準備）

來源：`AOC-vcs-version/hardware/src/{top.sv,CHIP.v}`、`src/AXI/{AR,AW}_decoder.sv`、
`src/EPU/EPU_Wrapper.sv`、`src/AXI_BRAM_Buffer_wrapper.sv`、`sim/fpga/{boot.c,main.c,link.ld,Makefile}`。

**匯流排拓樸（`top.sv` 內 `AXI_fifo` crossbar + CDC）**：
- masters：**M0 = CPU 讀、M1 = CPU 寫、M2 = DMA（讀寫）**。
- EPU **不是 master**，它是 **slave S6**；CPU/DMA 用 AXI 寫進它內部 GLB，再寫 start 暫存器啟動。

**位址 Map（解碼自 AR/AW_decoder + EPU_Wrapper + main.c）**：

| Slave | 模組 | Base | 解碼 | 用途 |
|---|---|---|---|---|
| S0 | `ROM_wrapper` | `0x0000_0000` | `addr[31:16]==0x0000` | 韌體 ROM（唯讀 `rom0-3.hex`）|
| S1 | `IM1`(SRAM) | `0x0001_0000` | `==0x0001` | IMEM |
| S2 | `DM1`(SRAM) | `0x0002_0000` | `==0x0002` | DMEM（含 DMA descriptor，`0x0002_FF00+`）|
| S3 | `DMA_wrapper` | `0x1002_0000` | `addr[31:16]==0x1000/0x1002` | DMA 暫存器（DMAEN=`+0x100`、DESC_BASE=`+0x200`）|
| S4 | `WDT_wrapper` | `0x1001_0000` | `==0x1001` | Watchdog |
| S5 | `AXI_BRAM_Buffer_wrapper` | `0x2000_0000` | `addr[31:24]==0x20` | **FPGA buffer（UART 要接的塊）** |
| S6 | `EPU_Wrapper` | `0x0003_0000` | `addr[31:16]==0x0003~0x0006` | EPU：GLB + start 暫存器 |

**EPU (S6) 內部位址**（`EPU_Wrapper.sv`）：System 埠 `A = addr[15:2]`（14-bit word）。
- 輸入 → word 0 → `0x0003_0000`；權重 → word 1024 → `0x0003_1000`。
- **start 暫存器**：`addr[18:16]==3'b110`（即 `0x0006_0000`），寫 `WDATA[0]=1` 拉 `EPU_start`；
  done 後發 `epu_interrupt`，ISR 寫 0 收回。result_valid/class/score 直接拉到頂層輸出。

**現行開機資料流（VCS 驗過，靠 ROM）**：`boot.c` 用 DMA 串 5 descriptor 一次搬：
ROM→IMEM(0x10000)、ROM→SDATA/DATA(0x20000)、**ROM→GLB 輸入@0x30000(544字)**、
ROM→GLB 權重@0x31000(3456字)；搬完 `main.c` 寫 `EPU_start=1`→`wfi`→EPU 算完中斷→讀 result。
→ **缺 `rom*.hex` 整顆不動**：碼/權重/輸入全靠 ROM 經 DMA 載入。

**新架構對應（雙模式骨架沿用、只改「輸入來源 + 觸發」）**：
- 模式1（單筆）：PC→ESP32→UART→**S5 buffer 第二埠**(544字) → 按鈕 → CPU 設
  DMA descriptor `S5(0x2000_0000)→GLB輸入(0x0003_0000) len=2176B` → 寫 `EPU_start` → 等中斷 → 讀 result。
- 模式2（即時 loop）：同上，觸發源「按鈕」換成 buffer 收滿 544 字的 `data_ready` 旗標，CPU 輪詢到就跑、再 loop。
- **權重只載一次**：開機照舊 ROM→GLB 權重@0x31000；每筆只搬輸入。

**韌體改動（小）**：① `boot.c` 保留 ROM→IMEM/DMEM/權重，**砍掉 ROM→GLB 輸入(DESC_3)**；
② `main.c` 改「等觸發→設 DMA(S5→GLB 輸入)→啟 EPU→讀 result」迴圈。

**還缺的 RTL（兩塊）**：
1. **S5 buffer 開第二埠**：現在 `AXI_BRAM_Buffer_wrapper` 內就一顆單埠 `SRAM_wrapper`（同 IMEM/DMEM），
   只有 AXI 一埠。要改 **true dual-port BRAM**：A 埠=AXI(CPU 讀)、B 埠=UART RX loader 寫；B1 的
   `uart_rx.sv`+框架解析可搬。
2. **CPU 可讀的觸發/狀態路徑**：目前無 GPIO/狀態 slave，CPU 讀不到按鈕/data_ready。(a) 加極小狀態暫存器
   slave 給 CPU 輪詢；或 (b) 把按鈕/data_ready OR 進現有中斷線(`DMA_interrupt||intr_epu`)。模式1用(a)最單純。
3. **CDC**：S5 在 `dram_clk` 域、UART 自有時脈→第二埠天然跨域（dual-port BRAM 允許兩埠異步）；
   「544 字到齊」的 data_ready 要 CDC 同步到 CPU 域。

**推進順序**：B0（整顆 CHIP 連現有 ROM 流程上板，需先有 `rom*.hex`）→ 加 buffer 第二埠+韌體改輸入來源（模式1）→ 自動觸發（模式2）。

**RISC-V 工具鏈（2026-06-14）**：裝在 **WSL2 Ubuntu-24.04**（已存在）。Claude Code 仍跑在 Windows，
經 `wsl bash -c "..."` 驅動；`D:\AOC-final` 在 WSL 為 `/mnt/d/AOC-final`（同一份檔），`make` 出的 hex
直接落 Windows 路徑，不需手動轉檔。分工：使用者裝 toolchain，Claude 寫 C/改 link.ld/呼叫 `make` 編 hex。
Makefile 需要 `riscv64-unknown-elf-{gcc,objdump,objcopy}`（`-march=rv32imf -mabi=ilp32`）+ `python3`。

### 9.Y B0：整顆 SoC FPGA build 完成、時序收斂、✅ 上板驗證通過（2026-06-14 晚）

工作目錄 `D:\AOC-final\chip_fpga\`（與 epu_fpga 的 V1/B1 分開）。產出：
- `rtl/chip_top.sv`：板級頂層。**MMCME2_BASE**（primitive，非 IP）100MHz 進 →
  **cpu_clk=100MHz**（CPU+EPU+IM1/DM1+DMA）、**axi/rom/dram=50MHz**（AXI crossbar+ROM+WDT+buffer）。
  reset 全 active-high、async-assert/sync-deassert、locked 閘控，釋放序 dram→rom→axi→cpu。
  result 鎖存 + LED mux（sw 選顯示）。**不需 start 按鈕**——CPU 靠韌體自走啟 EPU。
- `rtl/ROM_wrapper.sv`：overlay，`$readmemh` 用**絕對路徑** `D:/AOC-final/chip_fpga/rom*.hex`
  （裸檔名 Vivado 靜默忽略→ROM 全0，V1 踩過）。合成 log 確認 4 檔 `read successfully`。
- `rom0~3.hex`：由 `AOC-vcs-version/.../sim/fpga` `make` 編出後複製進來（現有 ROM 流程韌體，
  in.dat 烤在 ROM；模式1 再改 boot.c/main.c）。
- `constraints/chip_nexys_video.xdc`：clk R4 / rst BTNC / sw[1:0] / led[7:0] +
  `set_clock_groups -asynchronous`（CLKOUT0 vs CLKOUT1），讓 AXI async FIFO 跨域不被當單週期。
- `build_chip.tcl`：解析 `rtl_fpga_auto.f`（107 檔，去原 ROM_wrapper、去 stray svh）+ overlay +
  hex + 兩個 global include header（include/define.svh、include/AXI_define.svh）。
  impl 策略 `Performance_ExplorePostRoutePhysOpt`。執行：`cd chip_fpga; vivado -mode batch -source build_chip.tcl`。

**時序歷程（重要教訓）**：
- v1 單一 100MHz 餵 4 域 → **時序爆**（WNS −2.063ns / 2492 失敗），最差路徑全在
  `AXI_fifo/M2_DMA|M1` 的 async FIFO 指標——因 4 時脈共用一條淨線，CDC 跨域被當同步單週期算。
- v2 MMCM 拆 cpu100/axi50 + async clock groups → clk50 WNS +4.385/0 失敗、跨域清空，
  clk100 只剩 **WNS −0.100ns / 3 端點**（CPU mem_wb→if_id、EPU reducer 加法器，皆繞線主導）。
- v3 改 impl 策略 `Performance_ExplorePostRoutePhysOpt` → **WNS +0.089ns、0 失敗、0 critical**。✅
- 資源：LUT 25.0% / FF 10.3% / BRAM 25.2%(92 tile) / DSP 1.5% / MMCM 1 / BUFG 3。
- bit 版本（`chip_fpga/build/`）：`chip_top_v1_single100_timingfail.bit`（壞時序，參考）、
  `chip_top_v2_cpu100_wns-0p1.bit`（差 0.1ns）、`chip_top_v3_cpu100_axi50_PASS.bit`（過）。
  **release：`chip_fpga/release/chip_top_b0.bit`**（= v3，known-good 候選）。

**✅ 上板驗收通過（2026-06-14 晚，USB 隨身碟燒錄，免操作上電自走）**：
sw=00→`0x67`(103)、sw=01→LED7=valid 亮+LED2:0=class `000`(N)、sw=10→LED0~2 全亮
（locked+rst_done+valid）、sw=11→心跳。整顆手刻 SoC（RV32+FPU+AXI+DMA+L1/L2+WDT+ROM+EPU）
自走跑通、與 VCS golden 逐位元相符。⚠️ 燒錄前清隨身碟上層舊 bit（第7節坑）。

**下一步（模式1）**：把 boot.c 的 ROM→GLB 輸入(DESC_3) 砍掉、main.c 改「等觸發→DMA
搬 S5 buffer(0x2000_0000)→GLB 輸入(0x0003_0000)→啟 EPU→讀 result」迴圈；RTL 加 buffer
第二埠(UART 寫) + CPU 可讀觸發/狀態路徑。位址 map 見 9.X。

### 9.Z 模式1 M1a：韌體改走 buffer→GLB，✅ 上板驗證通過（2026-06-14 晚）

**目標**：純韌體（零新 RTL）把輸入路徑從「ROM 直入 GLB」改成「經 S5 buffer 中轉」，
驗證模式1 的核心資料路 CPU→DMA→buffer→GLB→EPU。沿用 B0 的 chip_fpga RTL/XDC/build，只換韌體。
韌體源碼版控於 `chip_fpga/firmware/`（boot.c/main.c/isr.S/setup.S/link.ld/Makefile/txt2bin.py/
in.dat/weight.dat）；對應修改也在 `AOC-vcs-version/.../sim/fpga/`（boot.c.orig/main.c.orig 為 B0 原版備份）。

**韌體改動**：
- `boot.c`：DESC_3 的 dst 從 `__input_glb_dst`(0x30000) 改成 `FPGA_BUFFER_BASE`(0x2000_0000)。
  輸入改 stage 到 buffer（模擬未來 UART 角色）；weight 仍 ROM→GLB(0x31000)；DESC 鏈不變。
- `main.c`：啟 EPU 前新增一段 DMA：descriptor(@0x2FF00){src=0x2000_0000, dst=0x30000,
  len=0x880=2176B, eoc=1} → 設 DESC_BASE(0x10020200)/DMAEN(0x10020100)=1 → `wfi`(等 DMA 完成
  中斷) → `EPU_start`(0x60000)=1 → `wfi`(等 EPU 完成) → 收尾。中斷處理 external_interrupt_handler
  在 DMA 完成清 DMAEN、EPU 完成清 EPU_start（兩個 wfi 共用 MEIP，已驗）。

**build/驗收**：`make` 重編 rom*.hex（rom0=13467B）→ 複製覆蓋 chip_fpga/rom*.hex → 重跑
build_chip.tcl（邏輯不變，WNS +0.022ns、0 失敗、ROM 載入新韌體）。bit 保留
`chip_fpga/build/chip_top_m1a_buffer2glb.bit`、release `chip_fpga/release/chip_top_m1a.bit`。
**上板（USB，免操作自走，不用按鈕）**：sw=00=`0x67`(N)、sw=01=valid+class000、
sw=10=locked+rst_done+valid、sw=11=心跳。**sw=00=0x67（非 0x6B）即鐵證**：輸入確實經
buffer→GLB（搬失敗則 GLB 輸入=0→class S/0x6B）。

**✅ M1b 完成（2026-06-15）：觸發改用 CPU reset，不走按鈕中斷。**
背景：CPU 內含 L1/L2 cache（CPU_wrapper 內），「CPU 輪詢 MMIO 狀態」有 stale-cache 風險、
且這顆學術 cache 的 cacheable 劃分不明；按鈕中斷又需 trig_clear 暫存器 + top/EPU_Wrapper/CHIP
overlay。**使用者提議用 CPU reset 當觸發**——FPGA **BRAM 內容不被 reset 清掉**（reset 只清
FSM/暫存器，不清 mem[] 陣列），所以 buffer 資料天生存活：按 BTNC reset → CPU 重開機 → boot
重載 weight（ROM→GLB）→ main DMA buffer→GLB→EPU。等於「按一下 reset = 用 buffer 當前內容
重新分類」。這避開中斷/cache/三檔 overlay，大幅簡化。
- **⚠️ 設計約束（使用者強調，務必遵守）**：資料 buffer 必須**永遠在 BRAM**、不可改放暫存器。
  reset-觸發完全仰賴「BRAM 不被 reset 清」；改放暫存器會被清掉，設計即垮。M1c 的 UART 寫入
  也必須寫進**同一塊 BRAM 陣列**（dual-port BRAM 第二埠），不可改架構。
- 產出（chip_fpga/）：`rtl/SRAM_wrapper_buf.sv`（複製 SRAM_wrapper + `$readmemh` 絕對路徑
  `buf_init.hex` 預載，`ram_style=block`；只給 S5 用，IM1/DM1 維持原 SRAM_wrapper）、
  `rtl/AXI_BRAM_Buffer_wrapper.sv`（overlay，實例化 SRAM_wrapper_buf）、`buf_init.hex`
  （=firmware/in.dat 544 字輸入）。`boot.c`：移除 ROM→buffer 那條 DESC（DESC_2.next→DESC_4），
  buffer 不再由 boot 載入。`main.c`：同 M1a（DMA buffer→GLB→EPU）。build_chip.tcl：多排除原
  AXI_BRAM_Buffer_wrapper、多收兩 overlay + buf_init.hex。
- build：WNS +0.062ns、0 失敗、0 critical，buf_init.hex/rom*.hex 確認載入。
  bit：`chip_fpga/build/chip_top_m1b_reset_trigger.bit`、release `chip_top_m1b.bit`。
- ✅ 上板：sw=00=0x67、sw=01=valid+class000、sw=10=locked+rst_done+valid、sw=11=心跳。
  證明解耦 buffer（boot 不載、buffer 獨立 BRAM、main 讀得到）。reset 重跑同資料仍 0x67
  （肉眼無差異，換資料的鐵證留 M1c）。

**M1c（下一步）**：buffer 開**第二埠**（true dual-port BRAM——在 SRAM_wrapper_buf 加 port B
寫埠，正確 TDP coding style 讓 Vivado infer BRAM，資料仍在 BRAM）。UART RX（搬 B1 的
`epu_fpga/rtl/uart_rx.sv` + 框架解析 AA55+2176B payload+XOR）把 544 字寫入 buffer port B；
`$readmemh` 預載當無 UART 時的 fallback。流程：UART 送幀 → 等收齊 → 按 **BTNC reset** →
CPU 重跑用新 buffer 內容分類。鐵證：送不同樣本 → 不同 class（如 test A：無輸入 S/0x6B、
有輸入 N/0x67）。UART/ESP32 接線沿用 B1（GPIO17→JA1/AB22 等）。
