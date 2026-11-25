RTL := gpu_engine.v gpu_regs.v vga_controller.v vram.v top_gpu.v
IVERILOG ?= iverilog
VVP ?= vvp

.PHONY: check engine synth-check
check:
	$(IVERILOG) -g2001 -Wall -s top_gpu -tnull $(RTL)

engine:
	@set -eu; d=$$(mktemp -d); trap 'rm -rf "$$d"' EXIT; \
	$(IVERILOG) -g2001 -s engine_tb -o "$$d/sim" gpu_engine.v bench/engine_tb.v; \
	$(VVP) "$$d/sim" > "$$d/log"; cat "$$d/log"; grep -qx 'PASS engine' "$$d/log"

# Keep the framebuffer as memory: this checks generic RTL synthesis, not placement or timing.
synth-check:
	yosys -Q -T -p 'read_verilog $(RTL); hierarchy -check -top top_gpu; proc; opt; memory -nomap; opt; check -assert; stat'

.PHONY: diff
diff:
	python3 tests/differential.py
