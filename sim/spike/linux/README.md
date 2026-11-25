# Spike 启动 RISC-V Linux：设备树与 DRM/KMS

在 ubuntu2404 的 `~/src/GlandaGPU/sim/spike` 目录运行：

```sh
bash linux/boot.sh            # 启动、保存串口日志，只有 guest /init 通过才返回 0
bash linux/boot.sh --shell    # 串口交互；在 guest 用 poweroff -f 关机
```

已生成的镜像位于 `build/linux/`。1 个 RV64 hart，256 MiB RAM，使用 OpenSBI 1.7、Linux 6.1.160、BusyBox 1.36.1 静态 initramfs。默认配置不绑定 GPU 驱动；下面的 `--drm` 独立配置会加载实际的 KMS 驱动。

## 设备树路径

在测试的 Spike `3d774fe978d8` 中，`--device=glandagpu` 会附加实际的 Verilated 设备，但 `--dump-dts` 只生成内建设备。`boot.sh` 用与实际启动相同的内存、内核、initrd 和命令行参数导出 `spike-base.dts`，在 `/soc` 下补 `gpu@40000000`（`compatible="glanda,gpu"`，`reg=<0 0x40000000 0 0x201000>`），再编译 `spike-linux.dtb`。实际启动时**同时**传 `--dtb` 和 `--device`；不需要改动 Spike 源码。DTC 在重编译反汇编得到的基础树时可能警告原有中断项用了数值 phandle；本次启动 UART 和 PLIC 均正常初始化。

Linux 的 `/init` 从 `/sys/firmware/devicetree/base` 读取 compatible 和大端 reg，并确认 `/sys/bus/platform/devices` 中有 `of_node` 指向同一节点，同时没有 driver 链接。成功标志为 `GLANDA-DT-PASS`；非交互模式看到它后结束模拟器，完整启动日志在 `build/linux/boot.log`。这验证的是 OF/platform 枚举，不是 GPU 功能探测。可在 guest 手动复验：

```sh
uname -a
tr '\000' '\n' </sys/firmware/devicetree/base/soc/gpu@40000000/compatible
od -An -tx1 /sys/firmware/devicetree/base/soc/gpu@40000000/reg
readlink -f /sys/bus/platform/devices/40000000.gpu/of_node
cat /sys/bus/platform/devices/40000000.gpu/modalias
poweroff -f
```

## 从源码重新生成

需要现有 Spike、Verilator、交叉工具链（`riscv64-linux-gnu-gcc` 和裸机工具链）、内核构建工具、dtc、curl、Python 3 和 dpkg-deb。首次准备固件和 BusyBox 时联网，并校验固定 SHA256。内核默认复用本机 `~/src/glanda-drm/kernel-work/linux-6.1.160`，所有产物都在 `build/linux`，不改原内核树。可用 `KERNEL_SRC` 指定干净的 Linux 6.1.160 源码，用 `KERNEL_TARBALL` 指定备用源码包。

```sh
make all
bash linux/prepare-firmware.sh
bash linux/build-kernel.sh
python3 linux/make-initrd.py
bash linux/boot.sh
```

## DRM/KMS 驱动与实际图像验证

[平台驱动](../../../linux/drm/glanda_drm.c) 的模块名为 `glanda_drm`，DRM 名称为 `glandakms`。设备树继续使用 `glanda,gpu`。在本机直接复验：

```sh
cd ~/src/GlandaGPU/sim/spike
bash linux/boot.sh --drm           # 自动验证，保存 build/linux/drm/kms.png
bash linux/boot.sh --drm --shell   # 在 guest 内可运行 kms-test &，用 kill $! 结束测试，poweroff -f 关机
```

如修改驱动或需要重建，在本目录先执行 `bash linux/build-drm.sh`，再执行 `python3 linux/make-initrd.py --drm`。该配置独立于无驱动测试；公用插件、OpenSBI 与 BusyBox 包。另需 RV64 Linux 交叉 libc 和 UAPI 头文件，自动 DRM 验收需要 `sha256sum` 和 `pnmtopng`（Ubuntu 包 `coreutils netpbm`，不依赖 Pillow）。交互时也可设置 `GLANDA_VGA_PPM="$PWD/build/linux/drm/live.ppm"` 持续抓取实际输出，完成一帧后原子替换。

验证链路：设备树平台匹配 → 加载模块 → 注册 DRM card → 客户端枚举 640×480 模式和 CRTC → 创建并 mmap dumb buffer → ADDFB2、SETCRTC → 修改局部矩形并 DIRTYFB → 比对 VGA 引脚采集的全部 307200 个像素。测试不使用 `/dev/mem` 或私有 ioctl。终端记录在 `build/linux/drm/boot.log`，最终 PNG 来自仿真帧，不是从 guest 缓冲区导出。

仅支持单显示管线、固定模式和线性 XRGB8888：驱动在提交时将影子缓冲转换成 RGB444，对每个像素作一次对齐的 32 位 MMIO 写。当前不使用 2D 命令引擎、不提供 3D 或 render node，也不支持硬件 vblank 中断或无撕裂翻页。此驱动面向 Linux 6.1.160，与 QEMU 的 PCI 驱动相互独立。

## Bash 入口与依赖

已有镜像时，启动流程只需 Bash、Linux 基础命令、与插件 ABI 匹配的 Spike 和 `dtc`。非交互 DRM 验收还要 `netpbm`：对本次抓取的规范 P6 帧（固定头与完整像素）计算 SHA256，与独立测试图公式的摘要比较，再转成 PNG。改变测试图或 PPM 编码后须同步更新参考摘要。重新打包 initramfs 仍使用 Python，但启动时不调用它。

可以从其他工作目录按脚本绝对路径启动；默认构建目录相对脚本定位。`SPIKE`、`DTC` 可指定工具路径，`GLANDA_BUILD` 可指定 `sim/spike/build` 的替代目录，`BOOT_TIMEOUT` 指定自动验收超时秒数（默认 120）。`bash -x linux/boot.sh --drm` 可打印实际执行的命令。原 `python3 linux/boot.py` 仅作兼容转发。
