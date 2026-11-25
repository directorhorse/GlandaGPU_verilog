# GlandaGPU 的 Verilog-2001 移植

基于上游 `eed04d0`，五个可综合模块均为独立的 Verilog 源码。顶层是 `top_gpu`；构建硬件无需 GHDL 或混合语言支持。原版 `../src/*.vhd` 和 VUnit 仿真保留作参考，不要把两套同名 RTL 一起加入工程。

| 模块 | 功能 |
| --- | --- |
| `top_gpu.v` | Avalon-MM 地址译码、显存仲裁、顶层连线 |
| `gpu_regs.v` | 命令和状态寄存器、中断使能及写 1 清除 |
| `gpu_engine.v` | 清屏、填充矩形、Bresenham 直线 |
| `vram.v` | 307200 × 12 位双端口同步显存 |
| `vga_controller.v` | 640 × 480 扫描、同步和 RGB444 输出 |

## 在 Ubuntu 中复验

```sh
# 如需安装：sudo apt install make python3 iverilog ghdl-mcode yosys
cd /home/directorhorse/src/GlandaGPU/verilog
make check        # 以 Verilog-2001 编译整个 top_gpu，检查端口连接
make engine       # 独立检查清屏的每个地址、边缘裁剪、反向直线和未知命令
make diff         # 用相同激励对比原版 VHDL 和 Verilog 的顶层输出
make synth-check  # Yosys 通用 RTL 综合检查，显存保留为 memory
```

差分测试使用 GHDL 与 Icarus；除对比两套 RTL 外，还用独立的预期图像核对 RGB、消隐和同步。这些是定向回归，不是形式等价证明。

## Quartus / Platform Designer

用 Quartus Prime 打开本目录中的 `GlandaGPU_Verilog.qpf`；沿用原工程的 Cyclone V 器件型号 `5CSXFC6D6F31C6`。使用 Platform Designer 时，把本目录加入 IP 搜索路径，选择 `GlandaGPU (Verilog)`。其组件标识为 `GlandaGPU_Verilog`，不会覆盖原 VHDL 组件。两个描述均使用原接口和字寻址约定：Avalon 地址位 19 选择寄存器区，字地址 `0x80000` 对应字节偏移 `0x200000`。本次未运行 Quartus 布局布线、静态时序分析或板级测试；综合后应检查 M10K 推断及资源报告。

## 兼容性说明

- 不改变上游绘图算法，包括矩形尺寸减 1 的 10 位回绕；宽或高为零并不表示空操作。
- 显存没有初始化或复位清零；仿真或软件应先清屏。超过帧缓冲深度的显存地址按上游行为映射到像素 0。
- 寄存器组合读使用 `always @*`。原 VHDL 的敏感列表遗漏了中断使能、挂起位和启动脉冲；若地址保持不变而只有这些信号变化，原版 RTL 仿真可能暂时显示旧值。Verilog 跟随组合硬件行为，不复刻这个仿真缺陷。
