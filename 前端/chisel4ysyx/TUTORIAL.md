# Chisel 数字电路实验工具链完整教程

这份文档只讲方法，不提供替你完成的实验答案。仓库中的 Chisel 源码以 Git
提交 `42a6d86` 为准；练习时应继续使用你自己在
`src/main/scala/ysyx/` 中写的模块。

建议只选一个有状态模块（例如 `shift`）从头走完一次完整流程。掌握生成 RTL、
自动仿真、波形和 NVBoard 接线以后，其他实验只需要复用工具链，不必每个都重新
搭一遍。

## 1. 你真正需要学到什么

完整流程是：

```text
Chisel 源码
  │  Mill + CIRCT
  ▼
SystemVerilog
  │  Verilator + testbench
  ├──────────────► 自动判断功能是否正确
  │
  ├──────────────► VCD 波形 ─► GTKWave
  │
  └──────────────► top.sv + top.nxdc + NVBoard
                              └► 图形化开关、按键、LED、VGA
```

做到下面这些就足够：

- 能读懂生成模块的端口名、方向和位宽。
- 能写测试，自动判断结果，而不是只看打印。
- 能从波形解释时钟、复位、输入和寄存器更新。
- 能写一个只做接口适配的 `top.sv`。
- 能解释一条 NXDC 映射中 Verilog 位和面板元件的对应关系。
- 能修改脚本和 Makefile 中的源文件、顶层名与路径。
- 能把一个自己写的 Chisel 模块完整接到 NVBoard。

不必自己重写 NVBoard 的 SDL 图形界面、C++ 库或每个实验的公共构建代码。

## 2. 各工具分别做什么

| 工具 | 作用 | 不负责什么 |
| --- | --- | --- |
| Chisel | 用 Scala 描述硬件并生成 RTL | 不直接显示电路运行窗口 |
| Mill | 编译 Scala、运行生成入口和测试 | 不代替 Verilator |
| CIRCT | 将 Chisel 中间表示降成 SystemVerilog | 不负责板级引脚 |
| Verilator | 把 Verilog/SystemVerilog 编译成可执行仿真器 | 不决定测试期望值 |
| VCD | 记录信号随仿真时间的变化 | 本身不是查看器 |
| GTKWave | 打开 VCD/FST 查看波形 | 不执行硬件逻辑 |
| NVBoard | 用软件模拟开关、按键、LED、数码管、VGA 等外设 | 不检查你的逻辑是否正确 |
| NXDC | 描述顶层端口与 NVBoard 元件的连接 | 不改变 Chisel 模块的功能 |

推荐顺序是“先自动测试，再波形，最后上 NVBoard”。面板接错时，前两层可以帮助
判断是核心逻辑错误还是接线错误。

## 3. 当前仓库的原始 Chisel 用法

主要源码在：

```text
src/main/scala/ysyx/practice.scala
src/main/scala/ysyx/generate.scala
```

`ysyx.GenAll` 会把若干模块生成到根目录的 `generated/`。在仓库根目录运行：

```sh
./mill --no-server chisel4ysyx.runMain ysyx.GenAll
```

`--no-server` 不是硬性要求，但在容器、多终端或 Mill daemon 锁异常时更稳定。

编译和运行测试：

```sh
./mill --no-server chisel4ysyx.compile
./mill --no-server chisel4ysyx.test
```

仓库的 `build.sbt` 仍含模板占位符，因此以 Mill 为主。只有在你先修正 sbt 配置
以后，才把 `sbt test` 当成等价检查。

### 单独生成一个模块

练习时最好给目标模块单独建立生成入口，避免每次混入无关 RTL：

```scala
package ysyx

import circt.stage.ChiselStage

object GenShift extends App {
  ChiselStage.emitSystemVerilogFile(
    new shift,
    Array("--target-dir", "practice/generated")
  )
}
```

这是生成入口，不是重写 `shift`。它只负责实例化你已经写好的 Chisel 模块。

运行：

```sh
./mill --no-server chisel4ysyx.runMain ysyx.GenShift
```

生成后先查看 `module shift(...)` 的端口。Chisel Bundle 的字段通常会成为
`io_op`、`io_in`、`io_out`；时钟和复位通常是 `clock`、`reset`。不要凭印象写
testbench 或顶层，应以实际生成文件为准。

## 4. 一个可靠的生成脚本怎么写

脚本最常见的问题是依赖当前工作目录。正确做法是先定位脚本自身，再计算仓库
根目录：

```bash
#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "${script_dir}/.." && pwd)"

cd "${repo_dir}"
./mill --no-server chisel4ysyx.runMain ysyx.GenShift
test -s "${script_dir}/generated/shift.sv"
```

这里三项很重要：

- `set -euo pipefail`：任何一步失败就停止，不拿旧产物继续构建。
- `script_dir`：脚本从其他目录调用时仍能找到文件。
- `test -s`：确认 RTL 确实生成且不是空文件。

验证路径是否可靠：

```sh
cd /tmp
/你的仓库绝对路径/practice/generate.sh
```

## 5. Verilator 自动仿真的原理

对于时序电路，测试节奏应固定为：

```text
设置输入
→ 时钟低电平
→ 产生上升沿
→ 等待少量传播时间
→ 检查输出
```

SystemVerilog testbench 的核心结构可以是：

```systemverilog
module testbench;
  logic clock = 0;
  logic reset = 0;
  logic [2:0] io_op = 0;
  logic io_in = 0;
  logic [7:0] io_out;

  shift dut (
    .clock(clock),
    .reset(reset),
    .io_op(io_op),
    .io_in(io_in),
    .io_out(io_out)
  );

  task tick;
    begin
      #1 clock = 0;
      #1 clock = 1;
      #1;
    end
  endtask

  task check(input logic [7:0] expected, input string name);
    begin
      if (io_out !== expected) begin
        $error("%s: expected=%02h actual=%02h", name, expected, io_out);
        $fatal(1);
      end
    end
  endtask

  initial begin
    reset = 1;
    tick();
    reset = 0;

    // 下面由你根据自己的八种操作填写输入、tick 和期望值。

    $display("PASS");
    $finish;
  end
endmodule
```

不要只 `$display` 输出，也不要在 testbench 里复制一份完全相同的硬件作为答案。
对每个输入直接计算期望的下一状态，并在错误时用非零状态结束。

一个可读的测试至少覆盖：

- 复位及运行中再次复位。
- 每个操作码。
- 全 0、全 1、最高位为 1、最低位为 1 等边界值。
- 串行输入为 0 和 1。
- 连续多个周期，确认状态确实逐拍变化。

Verilator 命令示例：

```sh
verilator --binary --timing \
  --top-module testbench \
  --Mdir build/obj_dir \
  generated/shift.sv test/testbench.sv

./build/obj_dir/Vtestbench
```

如果 CIRCT 生成的 SystemVerilog 含 `automatic logic` 等语法，而本机 Icarus
Verilog 无法解析，不代表 Chisel 一定错了。该仓库统一用 Verilator 更合适。

## 6. 波形怎么生成、怎么读

VCD 是仿真结果，GTKWave 只是查看器。可在 testbench 的 `initial` 中加入：

```systemverilog
$dumpfile("build/wave.vcd");
$dumpvars(0, testbench);
```

然后启用 trace：

```sh
verilator --binary --timing --trace \
  --top-module testbench \
  --Mdir build/wave_obj \
  generated/shift.sv test/testbench.sv

./build/wave_obj/Vtestbench
gtkwave build/wave.vcd
```

在 GTKWave 中至少加入 `clock`、`reset`、全部输入、输出和能看到的内部状态。
阅读时先找上升沿，再看该沿之前输入是什么，最后看沿后状态变成什么。

常见误判：

- 寄存器只在有效时钟沿更新，不会因为输入刚改变就立即更新。
- Chisel 的普通 `reset` 通常是同步复位；必须有有效时钟沿才生效。
- 在上升沿同一时刻立刻检查，可能看见旧值；应留一个小延迟。
- 组合输出可以随输入变化，寄存器输出要等时钟沿。

波形排错顺序：

```text
时钟是否翻转
→ 复位电平和有效沿是否正确
→ 输入是否在沿前稳定
→ 内部状态是否更新
→ 输出是否只是位序或极性错误
```

## 7. 为什么需要 `top.sv`

生成的 Chisel 模块是实验核心，而 NVBoard 希望看到统一、容易绑定的顶层端口。
`top.sv` 应只做：

- 实例化你的生成模块。
- 给信号改名或拆分/拼接位向量。
- 连接开关、按键、LED、数码管、键盘或 VGA。
- 必要时实现按键同步、边沿检测和消抖。

它不应重新实现 ALU、移位器、状态机等核心算法。否则面板上跑的是适配层中新写的
逻辑，而不是你的 Chisel。

示意：

```systemverilog
module top (
  input  logic       clk,
  input  logic       rst,
  input  logic [7:0] sw,
  input  logic [4:0] btn,
  output logic [15:0] ledr
);
  logic [7:0] result;

  shift u_shift (
    .clock (clk),
    .reset (rst),
    .io_op (sw[2:0]),
    .io_in (btn[0]),
    .io_out(result)
  );

  assign ledr = {8'b0, result};
endmodule
```

这只是接口示意。直接用高速 `clk` 时，状态会快速连续变化；若要肉眼单步，应把
按键同步到主时钟后做上升沿检测，产生单周期 `enable`。更规范的方式是在 Chisel
核心中使用时钟使能，而不是把普通按键信号直接当作新时钟。真实 FPGA 还要处理
机械按键消抖。

## 8. NXDC 引脚怎么匹配

NXDC 第一行声明 Verilog 顶层：

```text
top=top
```

随后把顶层端口与 NVBoard 元件绑定，例如：

```text
sw   (SW7, SW6, SW5, SW4, SW3, SW2, SW1, SW0)
btn  (BTNL, BTNU, BTNC, BTND, BTNR)
ledr (LD15, LD14, LD13, LD12, LD11, LD10, LD9, LD8,
      LD7, LD6, LD5, LD4, LD3, LD2, LD1, LD0)
```

必须同时检查三件事：

1. NXDC 左侧名称与 `top.sv` 端口完全一致。
2. 向量宽度一致。
3. 列表顺序与 Verilog 的高位到低位一致。

例如 `sw[7:0]` 对应上面的列表时，`sw[7]` 是 `SW7`，`sw[0]` 是 `SW0`。
如果你把列表反写，逻辑可能完全正确但面板位序相反。

数码管还要额外检查：

- 你的 Chisel 编码是 `gfedcba` 还是 `abcdefg`。
- NVBoard 绑定顺序是否包含小数点 `dp`。
- 输出是高电平点亮还是低电平点亮。

位序和有效电平应在 `top.sv` 做一次明确转换，不要偷偷改核心译码表。

## 9. NVBoard 的最小构建结构

建议单个练习使用：

```text
practice/
├── Makefile
├── generate.sh
├── run.sh
├── generated/
│   └── shift.sv
├── vsrc/
│   └── top.sv
├── test/
│   └── testbench.sv
└── constr/
    └── top.nxdc
```

NVBoard 官方仓库放在项目外或一个明确的依赖目录，并设置：

```sh
export NVBOARD_HOME=/绝对路径/NVBoard
```

Makefile 需要表达以下依赖关系：

```make
TOPNAME = top
NXDC_FILES = constr/top.nxdc
BUILD_DIR = build
OBJ_DIR = $(BUILD_DIR)/obj_dir
BIN = $(BUILD_DIR)/$(TOPNAME)

VSRCS = $(wildcard $(abspath vsrc)/*.sv) \
        $(wildcard $(abspath generated)/*.sv)
SRC_AUTO_BIND = $(abspath $(BUILD_DIR)/auto_bind.cpp)
CSRCS = $(abspath main.cpp) $(SRC_AUTO_BIND)

$(shell mkdir -p $(BUILD_DIR))

$(SRC_AUTO_BIND): $(NXDC_FILES)
	python3 $(NVBOARD_HOME)/scripts/auto_pin_bind.py $^ $@

include $(NVBOARD_HOME)/scripts/nvboard.mk

CXXFLAGS += -I$(NVBOARD_USR_INC) -DTOP_NAME=\"V$(TOPNAME)\"

$(BIN): $(VSRCS) $(CSRCS) $(NVBOARD_ARCHIVE)
	verilator -MMD --build -cc -O3 \
	  --top-module $(TOPNAME) $(VSRCS) $(CSRCS) $(NVBOARD_ARCHIVE) \
	  $(addprefix -CFLAGS ,$(CXXFLAGS)) \
	  $(addprefix -LDFLAGS ,$(LDFLAGS)) \
	  --Mdir $(OBJ_DIR) --exe -o $(abspath $(BIN))

all: $(BIN)

run: $(BIN)
	./$(BIN)

clean:
	rm -rf $(BUILD_DIR)

.PHONY: all run clean
```

Makefile 的命令行开头必须是 Tab。`main.cpp` 至少需要：

1. 包含 `nvboard.h` 和 Verilator 生成的 `Vtop.h`。
2. 调用 `nvboard_bind_all_pins`。
3. 调用 `nvboard_init()`。
4. 在循环中调用 `nvboard_update()`。
5. 每轮驱动一次低电平和高电平并调用 `eval()`。

运行脚本可按以下结构写：

```bash
#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
: "${NVBOARD_HOME:?请先设置 NVBOARD_HOME}"

"${script_dir}/generate.sh"
make -C "${script_dir}" run
```

## 10. 键盘实验为什么容易“不能用”

PS/2 接收器看的是时钟下降沿，并逐位收集起始位、8 位数据、奇偶校验位和停止位。
排查时分成三层：

```text
NVBoard 是否产生 PS/2 信号
→ 顶层端口和 NXDC 是否接对
→ Chisel 状态机是否正确解析帧
```

经验：

- PS/2 时钟空闲态通常为高。若复位时把“上一拍时钟”初始化为低，复位解除后可能
  虚构出一个下降沿，导致整个帧错一位。
- NVBoard 窗口必须获得键盘焦点；点击画出的键帽不等于发送真实键盘扫描码。
- 按下和松开会产生不同扫描码；扩展键还可能有前缀，状态机必须按实验要求处理。
- 先在波形里观察 `ps2_clk`、`ps2_data`、位计数和移位寄存器，再看数码管。
- 如果自动 testbench 能喂入完整帧并通过，而面板不响应，优先检查绑定、焦点和
  NVBoard 输入行为，不要立即重写接收器。

## 11. VGA 窗口、尺寸与碰撞问题

VGA 控制器输出的是逐像素扫描时序，不是让程序创建一个任意尺寸的第二窗口。
NVBoard 通常把 VGA 显示区域集成在主面板窗口中，因此“没有单独碰撞窗口”不一定
是错误。

以常见 640×480@60 Hz 时序为例：

- 可见区域是 640×480。
- 一整行还包含前沿、同步脉冲和后沿，总计常为 800 个像素时钟。
- 一整帧总计常为 525 行。

所以 800×525 是扫描总范围，不是可见画布大小。图形尺寸应由可见坐标范围和
图像边界决定，NVBoard 外层窗口尺寸还会受面板布局和显示缩放影响。

VGA 排错顺序：

1. 先只画固定颜色，确认 `hsync`、`vsync` 和有效显示区。
2. 再用 `x/y` 坐标画静态矩形。
3. 最后加入每帧更新一次的位置和速度。
4. 位置寄存器应在帧边界更新，不能每个像素时钟更新，否则移动快到看不见。
5. 碰撞判断应检查“下一位置是否越界”，或在当前位置到达边界时先反向，避免
   图形先越界一帧。

若你期望矩形宽 `W`、可见宽度 `640`，左上角横坐标的合法范围通常是
`0` 到 `640-W`，而不是到 `639`。纵向同理。把 800×525 当作可见区会导致物体
消失到消隐区，视觉上就像碰撞窗口或边界不对。

## 12. 之前最有价值的错误与经验

### 生成了 RTL，却没有运行你的 Chisel

症状：为了适配板子，在 `top.sv` 里重新写了一套核心逻辑。

原则：顶层只做连接、极性/位序转换、同步与必要的使能；实验算法必须实例化生成
的 Chisel 模块。需要新端口时，优先在你自己的 Chisel 接口中有意识地增加。

### 脚本只能在某个目录运行

原因：使用相对当前目录的路径。解决：所有脚本先计算 `script_dir`，再使用绝对
路径或 `make -C`。

### 旧生成文件掩盖了失败

原因：生成命令失败，但后续仍编译上一次的 `.sv`。解决：脚本遇错退出，并用
`test -s` 检查目标；调试时删除对应 `build/` 后重建。

### testbench 看见旧状态

原因：输入建立时间不对，或在时钟沿同一仿真时刻检查。解决：沿前设置输入，沿后
等待一个小延迟，再比较。

### 数码管、LED 看起来“逻辑反了”

原因通常是位序或有效电平，不一定是译码算法。先逐位追踪：

```text
Chisel 位 → 生成 Verilog 位 → top.sv 转换 → NXDC 元件
```

### 键盘第一帧错位

检查 PS/2 空闲高电平、下降沿检测寄存器的复位值、起始位和位计数，不要只盯最终
扫描码。

### VGA 大小和预期不同

区分扫描总尺寸、可见尺寸、图形尺寸与 NVBoard GUI 窗口尺寸。碰撞边界使用
可见区减去图形尺寸。

## 13. 推荐的一次完整个人练习

用你原来的 `shift` 完成以下内容即可，预计 6～10 小时：

1. 读接口并列出每个端口的方向、宽度和意义。
2. 自己写单模块生成入口与 `generate.sh`。
3. 自己写覆盖复位和八种操作的自动 testbench。
4. 生成 VCD，在 GTKWave 中解释至少三个连续时钟周期。
5. 自己写只做连接的 `top.sv`。
6. 自己写 NXDC，并解释三条具体映射。
7. 自己写或理解 Makefile 与 `run.sh`。
8. 删除 `build/` 后，从其他工作目录重新生成、测试和启动。

完成后，能不看答案回答以下问题，就已经达到练习效果：

- 为什么状态只在时钟沿变化？
- 测试为什么要在沿后延迟再检查？
- 某个 Chisel 位最终接到了哪个 NVBoard 元件？
- 为什么顶层适配不等于重写核心？
- 如果面板错而自动测试对，下一步查哪一层？
- 真实 FPGA 相比 NVBoard 还需要考虑哪些同步、消抖和时序问题？

其他实验可以复用同一套目录和脚本，只替换生成模块、测试向量、顶层接口和 NXDC
映射。真正值得亲手做一遍的是完整流程，而不是机械复制十二遍构建文件。
