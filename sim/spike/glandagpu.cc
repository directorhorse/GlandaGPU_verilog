// External Spike --device=glandagpu bridge. The model owns all GPU state.
#include "Vtop_gpu.h"
#include "vga_capture.h"
#include "riscv/abstract_device.h"

namespace {
constexpr reg_t kBase = 0x40000000;
constexpr reg_t kRegisters = 0x200000;
constexpr reg_t kLength = kRegisters + 0x1000;

class glandagpu_t final : public abstract_device_t {
 public:
  glandagpu_t() {
    rtl.clk = 0;
    rtl.reset = 1;
    rtl.avs_address = rtl.avs_writedata = 0;
    rtl.avs_read = rtl.avs_write = 0;
    rtl.eval();
    cycle();
    rtl.reset = 0;
    rtl.eval();
  }
  ~glandagpu_t() override { rtl.final(); }
  reg_t size() override { return kLength; }

  bool load(reg_t addr, size_t len, uint8_t* bytes) override {
    if (!valid(addr, len)) return false;
    begin(addr, false, 0);
    // Registers are a combinational mux: sample at acceptance, before any
    // STATUS/IP changes on the rising edge. VRAM's output is registered.
    uint32_t value = rtl.avs_readdata;
    bus_cycle();
    if (addr < kRegisters) value = rtl.avs_readdata;
    end();
    for (unsigned i = 0; i < 4; ++i) bytes[i] = uint8_t(value >> (8 * i));
    return true;
  }

  bool store(reg_t addr, size_t len, const uint8_t* bytes) override {
    if (!valid(addr, len)) return false;
    uint32_t value = 0;
    for (unsigned i = 0; i < 4; ++i) value |= uint32_t(bytes[i]) << (8 * i);
    begin(addr, true, value);
    bus_cycle();
    end();
    return true;
  }

  void tick(reg_t rtc_ticks) override {
    // Spike supplies 10 MHz RTC ticks; the GPU uses a nominal 25 MHz clock.
    // Retain half cycles across odd tick counts. MMIO already advanced the
    // model in this interval; a long blocking wait may exceed its budget.
    reg_t halves = 5 * rtc_ticks + half_cycle;
    half_cycle = halves & 1;
    for (reg_t n = mmio_cycles; n < halves / 2; ++n) cycle();
    mmio_cycles = 0;
  }

 private:
  Vtop_gpu rtl;
  const std::unique_ptr<glanda::VgaCapture> capture = glanda::VgaCapture::from_env();
  reg_t mmio_cycles = 0;
  unsigned half_cycle = 0;

  static bool valid(reg_t addr, size_t len) {
    return len == 4 && (addr & 3) == 0 && addr <= kLength - 4;
  }
  void cycle() {
    rtl.clk = 1;
    rtl.eval();
    if (capture) capture->sample(rtl.hsync, rtl.vsync, rtl.video_on, rtl.red, rtl.green, rtl.blue);
    rtl.clk = 0;
    rtl.eval();
  }
  void bus_cycle() { cycle(); ++mmio_cycles; }
  void begin(reg_t addr, bool write, uint32_t value) {
    rtl.avs_address = addr >> 2;  // Spike byte offset to Avalon word address
    rtl.avs_writedata = value;
    rtl.avs_read = !write;
    rtl.avs_write = write;
    rtl.eval();
    while (rtl.avs_waitrequest) bus_cycle();  // Hold request stable until ready.
  }
  void end() {
    rtl.avs_read = rtl.avs_write = 0;
    rtl.eval();
  }
};

glandagpu_t* parse(const void*, const sim_t*, reg_t* base,
                   const std::vector<std::string>& args) {
  if (!args.empty()) throw std::invalid_argument("glandagpu takes no arguments");
  *base = kBase;
  return new glandagpu_t;
}

std::string generate(const sim_t*, const std::vector<std::string>&) {
  return "    gpu@40000000 {\n"
         "      compatible = \"glanda,gpu\";\n"
         "      reg = <0x0 0x40000000 0x0 0x201000>;\n"
         "    };\n";
}

REGISTER_DEVICE(glandagpu, parse, generate)
}  // namespace
