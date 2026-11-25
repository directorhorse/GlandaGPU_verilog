SPIKE ?= spike
SPIKE_INCLUDE ?= /usr/local/include
VERILATOR ?= verilator
CROSS ?= riscv64-unknown-elf-
BUILD := $(abspath build)
PLUGIN := $(BUILD)/model/libglandagpu.so
ELF := $(BUILD)/smoke.elf
RTL := $(addprefix ../../verilog/,top_gpu.v gpu_regs.v gpu_engine.v vram.v vga_controller.v)

.PHONY: all smoke
all: $(PLUGIN) $(ELF)

$(PLUGIN): glandagpu.cc vga_capture.h $(RTL) Makefile
	mkdir -p $(BUILD)/model
	$(VERILATOR) --cc --exe --build --top-module top_gpu --Mdir $(BUILD)/model \
	  -Wno-fatal -CFLAGS '-std=c++20 -fPIC -I$(SPIKE_INCLUDE)' -LDFLAGS '-shared -pthread' \
	  -o libglandagpu.so $(RTL) $(abspath glandagpu.cc)

$(BUILD)/%.elf: %.S smoke.ld Makefile
	mkdir -p $(BUILD)
	$(CROSS)gcc -march=rv64i -mabi=lp64 -nostdlib -nostartfiles -static \
	  -Wl,--build-id=none,-T,smoke.ld -o $@ $<

smoke: all
	timeout 30s $(SPIKE) --isa=rv64i -m64 --extlib=$(PLUGIN) --device=glandagpu $(ELF)
	@echo 'PASS: Spike + Verilated GlandaGPU (20 guest checks)'

.PHONY: video view
video view: $(PLUGIN) $(BUILD)/video.elf
	python3 run_video.py --build "$(BUILD)" --spike "$(SPIKE)" $(if $(filter view,$@),--window $(VIEW_ARGS))
