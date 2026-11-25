# Spike + Verilator：GlandaGPU 裸机冒烟测试

在 WSL Ubuntu 24.04 中运行 `make smoke`。它从 `../../verilog/` 的五个模块生成主机插件，交叉编译不依赖 libc/pk 的 RV64I ELF，用 Spike 运行并检查退出码；不会生成显示窗口。无需改动 Spike 或 GPU RTL。

```sh
cd /home/directorhorse/src/GlandaGPU/sim/spike
make smoke
# PASS: Spike + Verilated GlandaGPU (20 guest checks)
```

## 主机环境（本机已安装）

测试版本：Verilator 5.020，riscv64-unknown-elf-gcc 13.2，Spike `3d774fe978d8cf6f7e08a7c5c8f8e9dad05bed68`。Spike 的 C++ 设备 API 与版本有关，插件头文件和正在运行的 Spike 应来自同一版本。全新环境可用：

```sh
sudo apt install build-essential git verilator gcc-riscv64-unknown-elf device-tree-compiler libboost-regex-dev libboost-system-dev libfdt-dev
# 在独立的源码目录构建 Spike，而不是在 GPU 工程内构建：
git clone https://github.com/riscv-software-src/riscv-isa-sim.git
cd riscv-isa-sim
git checkout 3d774fe978d8cf6f7e08a7c5c8f8e9dad05bed68
git submodule update --init --recursive
mkdir build-local && cd build-local
../configure --prefix=/usr/local CXXFLAGS='-O1 -g0' CFLAGS='-O1 -g0 -Wno-error=maybe-uninitialized'
make -j8
sudo make install && sudo ldconfig
```

`make all` 只构建。手动运行（成功时 Spike 本身不输出 PASS，退出码为 0）：

```sh
spike --isa=rv64i -m64 --extlib="$PWD/build/model/libglandagpu.so" \
  --device=glandagpu build/smoke.elf
```

## 接口与验证范围

- 物理基址 `0x40000000`，窗口长度 `0x201000`，寄存器起点 `0x40200000`。仅支持 4 字节对齐的 32 位小端访问。窗口内保留原 RTL 别名行为；软件请只使用有效的像素和寄存器地址。
- `glandagpu.cc` 只翻译 MMIO、驱动 `clk/reset`、等待 `waitrequest`，不模拟绘图，不保存影子显存。寄存器读在接受沿前采样，VRAM 读在该沿后采样。
- 即使没有 MMIO，也用 Spike 的设备 `tick` 推进 GPU（默认 10 MHz RTC 对应近似 25 MHz GPU）。一个 tick 间隔内扣除已执行的总线周期；长时间阻塞访问可超出该间隔预算。此设计用于功能验证，不用于测量 CPU 或总线延迟。
- `smoke.S` 的每个 `expect`/`pixel` 有独立的失败码（1–20）。检查相邻显存地址、RGB444 掩码、清屏时的阻塞读、矩形和直线绘制结果、DONE 挂起位与写 1 清除；矩形测试特意让 CPU 空转而不轮询 GPU。正常时通过 `tohost=1` 退出，超时不会被当成通过。
- 未转发 GPU `irq` 至 PLIC，也未在此配置下启动 Linux。

## VGA 抓帧与 WSLg 窗口

```sh
cd /home/directorhorse/src/GlandaGPU/sim/spike
make video     # 无窗口：运行 video.S，通过核对后写 build/vga.png 和 build/vga.ppm
make view      # WSLg：运行同一仿真，窗口轮询最新完整帧；结束后保留最后画面直到关闭
make smoke     # 原有 20 项测试，默认不启用视频采集
```

窗口由 WSLg + Python Tk 显示（首次可安装 `sudo apt install python3-tk`）。窗口只读取插件发布的完整 PPM 帧，不读取 RTL 内部显存。显示采用最新帧策略，主机较忙时可跳过中间帧，并非与墙钟锁定的 60 Hz。无 WSLg 或 SSH 环境请用 `make video`。

抓取自己的 ELF 不需要 Python 窗口。给原 Spike 命令加上 `GLANDA_VGA_PPM` 即可，例如：

```sh
GLANDA_VGA_PPM="$PWD/build/my-frame.ppm" spike --isa=rv64i -m64 \
  --extlib="$PWD/build/model/libglandagpu.so" --device=glandagpu path/to/program.elf
```

目标目录必须已存在。采集器先等待帧同步，再按 `video_on` 取有效像素；RGB444 每通道复制半字节得到 RGB888。同步后每幅完整帧原子替换同一文件，不累计到磁盘。仿真若在第一个完整帧结束前退出，不会产生新图像；请让 guest 在最后一次绘制后继续运行多个场同步周期。示例使用私有临时目录，避免用上次输出误判本次通过。
