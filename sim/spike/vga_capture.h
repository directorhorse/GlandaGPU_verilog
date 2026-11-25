#pragma once

#include <array>
#include <cerrno>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <memory>
#include <string>
#include <unistd.h>

namespace glanda {

class VgaCapture {
 public:
  static std::unique_ptr<VgaCapture> from_env() {
    const char* path = std::getenv("GLANDA_VGA_PPM");
    return std::unique_ptr<VgaCapture>(path && *path ? new VgaCapture(path) : nullptr);
  }

  // Called once per pixel clock, with settled, pipelined VGA outputs.
  void sample(bool hsync, bool vsync, bool active, uint8_t r, uint8_t g, uint8_t b) {
    const bool frame_edge = prev_v_ && !vsync;
    const bool line_edge = prev_h_ && !hsync;
    prev_h_ = hsync;
    prev_v_ = vsync;
    if (frame_edge) {
      if (valid_ && rows_ == height && x_ == 0 && !active) publish();
      valid_ = true;
      rows_ = x_ = 0;
      run_ended_ = false;
    }
    if (!valid_) return;  // Startup or malformed frame: wait for vertical sync.
    if (line_edge) {
      if (x_ == width) ++rows_;
      else if (x_ || (rows_ && rows_ < height)) valid_ = false;
      x_ = 0;
      run_ended_ = false;
    }
    if (!active) {
      if (x_) run_ended_ = true;
      return;
    }
    if (!hsync || !vsync || run_ended_ || rows_ >= height || x_ >= width) {
      valid_ = false;
      return;
    }
    const unsigned offset = 3 * (rows_ * width + x_++);
    pixels_[offset] = r * 17;
    pixels_[offset + 1] = g * 17;
    pixels_[offset + 2] = b * 17;
  }

 private:
  static constexpr unsigned width = 640, height = 480;
  explicit VgaCapture(const char* path) : path_(path) {}
  std::string path_;
  std::array<uint8_t, width * height * 3> pixels_;
  unsigned rows_ = 0, x_ = 0;
  bool prev_h_ = false, prev_v_ = false, valid_ = false, run_ended_ = false;
  bool reported_ = false;

  void error(int err) {
    if (!reported_) std::fprintf(stderr, "GLANDA_VGA_PPM: %s: %s\n", path_.c_str(), std::strerror(err));
    reported_ = true;
  }

  void publish() {
    // Same directory => rename replaces the previous complete frame atomically.
    std::string tmp = path_ + ".XXXXXX";
    const int fd = ::mkstemp(&tmp[0]);
    if (fd < 0) { error(errno); return; }
    std::FILE* f = ::fdopen(fd, "wb");
    int err = 0;
    if (f) {
      if (std::fprintf(f, "P6\n%u %u\n255\n", width, height) < 0 ||
          std::fwrite(pixels_.data(), 1, pixels_.size(), f) != pixels_.size()) err = errno ? errno : EIO;
      if (std::fclose(f) != 0) err = errno;
    } else {
      err = errno;
      ::close(fd);
    }
    if (!err && std::rename(tmp.c_str(), path_.c_str()) != 0) err = errno;
    if (err) {
      ::unlink(tmp.c_str());
      error(err);
    } else {
      reported_ = false;
    }
  }
};

}  // namespace glanda
