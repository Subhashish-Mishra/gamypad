#include "DualSense.h"
#include "LastError.h"

#include <algorithm>
#include <chrono>
#include <cstddef>
#include <fcntl.h>
#include <linux/uhid.h>
#include <poll.h>
#include <sys/random.h>
#include <unistd.h>

namespace {

using Clock = std::chrono::steady_clock;

const uint16_t kVendorSony = 0x054c;
const uint16_t kProductDualSense = 0x0ce6;
const int kInputReportSize = 64; // report id + 63 bytes
const auto kReportInterval = std::chrono::milliseconds(8); // ~125 Hz

// Motion arrives as a sample every ~20 ms. If it stops (gyro switched off on
// the phone), a held rate would spin the camera forever: zero it after this.
const int64_t kMotionStaleUs = 250000;

// Raw sensor scale advertised in the calibration report below.
//   gyro : 16 LSB per deg/s    (±2000 deg/s fills an int16)
//   accel: 8192 LSB per g
const int kGyroLsbPerDps = 16;
const int kAccelLsbPerG = 8192;

// The DualSense USB HID report descriptor: input report 0x01 (63 bytes), output
// 0x02, and the feature reports hid-playstation and SDL query.
const uint8_t kReportDescriptor[] = {
    0x05, 0x01, 0x09, 0x05, 0xA1, 0x01, 0x85, 0x01, 0x09, 0x30, 0x09, 0x31,
    0x09, 0x32, 0x09, 0x35, 0x09, 0x33, 0x09, 0x34, 0x15, 0x00, 0x26, 0xFF,
    0x00, 0x75, 0x08, 0x95, 0x06, 0x81, 0x02, 0x06, 0x00, 0xFF, 0x09, 0x20,
    0x95, 0x01, 0x81, 0x02, 0x05, 0x01, 0x09, 0x39, 0x15, 0x00, 0x25, 0x07,
    0x35, 0x00, 0x46, 0x3B, 0x01, 0x65, 0x14, 0x75, 0x04, 0x95, 0x01, 0x81,
    0x42, 0x65, 0x00, 0x05, 0x09, 0x19, 0x01, 0x29, 0x0F, 0x15, 0x00, 0x25,
    0x01, 0x75, 0x01, 0x95, 0x0F, 0x81, 0x02, 0x06, 0x00, 0xFF, 0x09, 0x21,
    0x95, 0x0D, 0x81, 0x02, 0x06, 0x00, 0xFF, 0x09, 0x22, 0x15, 0x00, 0x26,
    0xFF, 0x00, 0x75, 0x08, 0x95, 0x34, 0x81, 0x02, 0x85, 0x02, 0x09, 0x23,
    0x95, 0x2F, 0x91, 0x02, 0x85, 0x05, 0x09, 0x33, 0x95, 0x28, 0xB1, 0x02,
    0x85, 0x08, 0x09, 0x34, 0x95, 0x2F, 0xB1, 0x02, 0x85, 0x09, 0x09, 0x24,
    0x95, 0x13, 0xB1, 0x02, 0x85, 0x0A, 0x09, 0x25, 0x95, 0x1A, 0xB1, 0x02,
    0x85, 0x20, 0x09, 0x26, 0x95, 0x3F, 0xB1, 0x02, 0x85, 0x21, 0x09, 0x27,
    0x95, 0x04, 0xB1, 0x02, 0x85, 0x22, 0x09, 0x40, 0x95, 0x3F, 0xB1, 0x02,
    0x85, 0x80, 0x09, 0x28, 0x95, 0x3F, 0xB1, 0x02, 0x85, 0x81, 0x09, 0x29,
    0x95, 0x3F, 0xB1, 0x02, 0x85, 0x82, 0x09, 0x2A, 0x95, 0x09, 0xB1, 0x02,
    0x85, 0x83, 0x09, 0x2B, 0x95, 0x3F, 0xB1, 0x02, 0x85, 0x84, 0x09, 0x2C,
    0x95, 0x3F, 0xB1, 0x02, 0x85, 0x85, 0x09, 0x2D, 0x95, 0x02, 0xB1, 0x02,
    0x85, 0xA0, 0x09, 0x2E, 0x95, 0x01, 0xB1, 0x02, 0x85, 0xE0, 0x09, 0x2F,
    0x95, 0x3F, 0xB1, 0x02, 0x85, 0xF0, 0x09, 0x30, 0x95, 0x3F, 0xB1, 0x02,
    0x85, 0xF1, 0x09, 0x31, 0x95, 0x3F, 0xB1, 0x02, 0x85, 0xF2, 0x09, 0x32,
    0x95, 0x0F, 0xB1, 0x02, 0x85, 0xF4, 0x09, 0x35, 0x95, 0x3F, 0xB1, 0x02,
    0x85, 0xF5, 0x09, 0x36, 0x95, 0x03, 0xB1, 0x02, 0xC0};

int64_t nowUs() {
  return std::chrono::duration_cast<std::chrono::microseconds>(
             Clock::now().time_since_epoch())
      .count();
}

void putLe16(uint8_t *buf, int off, int value) {
  buf[off] = value & 0xFF;
  buf[off + 1] = (value >> 8) & 0xFF;
}

void putLe32(uint8_t *buf, int off, uint32_t value) {
  for (int i = 0; i < 4; i++)
    buf[off + i] = (value >> (8 * i)) & 0xFF;
}

int16_t clamp16(long long v) {
  return (int16_t)std::max<long long>(-32767, std::min<long long>(32767, v));
}

// Wire stick units (-32767..32767) -> 0..255 with 128 as centre.
uint8_t stickByte(int v) {
  long long b = 128 + (long long)v * 127 / 32767;
  return (uint8_t)std::max<long long>(0, std::min<long long>(255, b));
}

// Hat switch values: 0 = up, then clockwise to 7 = up-left; 8 = released.
uint8_t hatValue(int x, int y) {
  if (x == 0 && y == 0) return 8;
  if (x == 0) return y < 0 ? 0 : 4;
  if (y == 0) return x > 0 ? 2 : 6;
  if (x > 0) return y < 0 ? 1 : 3;
  return y < 0 ? 7 : 5;
}

uint8_t macTail[2];

} // namespace

DualSense::DualSense() {
  fd = open("/dev/uhid", O_RDWR | O_CLOEXEC | O_NONBLOCK);
  if (fd < 0) {
    setLastError("open /dev/uhid");
    return;
  }

  // Two controllers must not share a MAC: hid-playstation refuses duplicates.
  if (getrandom(macTail, sizeof(macTail), 0) < 0) {
    macTail[0] = (uint8_t)getpid();
    macTail[1] = (uint8_t)(nowUs() & 0xFF);
  }

  // The kernel probes the new device on a worker, and the driver asks for
  // feature reports while it does. Something has to be answering by then.
  running = true;
  worker = std::thread(&DualSense::loop, this);

  uhid_event ev{};
  ev.type = UHID_CREATE2;
  strncpy((char *)ev.u.create2.name, "DualSense Wireless Controller",
          sizeof(ev.u.create2.name) - 1);
  ev.u.create2.rd_size = sizeof(kReportDescriptor);
  ev.u.create2.bus = 0x03; // BUS_USB
  ev.u.create2.vendor = kVendorSony;
  ev.u.create2.product = kProductDualSense;
  ev.u.create2.version = 0x0100;
  ev.u.create2.country = 0;
  memcpy(ev.u.create2.rd_data, kReportDescriptor, sizeof(kReportDescriptor));
  if (write(fd, &ev, sizeof(ev)) < 0) {
    setLastError("create uhid device");
    running = false;
    worker.join();
    close(fd);
    fd = -1;
    return;
  }

  // Wait for the driver to finish probing: it reads the calibration report
  // last. If hid-playstation is not available the wait times out and the
  // device still works as a bare HID device.
  for (int i = 0; i < 300 && !calibrated; i++)
    usleep(10000);
  usleep(300000); // let the input nodes appear
  created = true;
}

DualSense::~DualSense() {
  running = false;
  if (worker.joinable()) worker.join();
  if (fd >= 0) {
    uhid_event ev{};
    ev.type = UHID_DESTROY;
    if (write(fd, &ev, sizeof(ev)) < 0) {
      // Closing the fd destroys the device anyway.
    }
    close(fd);
  }
}

void DualSense::loop() {
  auto next = Clock::now();
  while (running) {
    auto now = Clock::now();
    int wait = (int)std::chrono::duration_cast<std::chrono::milliseconds>(
                   next > now ? next - now : Clock::duration::zero())
                   .count();
    pollfd p{fd, POLLIN, 0};
    if (poll(&p, 1, wait) > 0 && (p.revents & POLLIN)) {
      uhid_event ev;
      while (read(fd, &ev, sizeof(ev)) == (ssize_t)sizeof(ev)) {
        switch (ev.type) {
        case UHID_START:
          started = true;
          break;
        case UHID_GET_REPORT:
          answerFeature(ev.u.get_report.id, ev.u.get_report.rnum);
          break;
        case UHID_SET_REPORT: {
          uhid_event reply{};
          reply.type = UHID_SET_REPORT_REPLY;
          reply.u.set_report_reply.id = ev.u.set_report.id;
          reply.u.set_report_reply.err = 0;
          if (write(fd, &reply, sizeof(reply)) < 0) {}
          break;
        }
        default: // UHID_OUTPUT (rumble, LEDs), OPEN, CLOSE, STOP: unused
          break;
        }
      }
    }
    if (Clock::now() >= next) {
      if (started) sendReport();
      next = std::max(next + kReportInterval, Clock::now());
    }
  }
}

void DualSense::answerFeature(uint32_t id, uint8_t reportNumber) {
  uhid_event reply{};
  reply.type = UHID_GET_REPORT_REPLY;
  reply.u.get_report_reply.id = id;
  uint8_t *d = reply.u.get_report_reply.data;
  int size = 0;

  switch (reportNumber) {
  case 0x05: { // calibration
    size = 41;
    d[0] = 0x05;
    // Biases (pitch, yaw, roll) stay 0. Plus/minus pairs set 16 LSB per deg/s.
    const int span = 540 * kGyroLsbPerDps;
    for (int i = 0; i < 3; i++) {
      putLe16(d, 7 + i * 4, span);
      putLe16(d, 9 + i * 4, -span);
    }
    putLe16(d, 19, 540); // gyro speed plus
    putLe16(d, 21, 540); // gyro speed minus
    for (int i = 0; i < 3; i++) {
      putLe16(d, 23 + i * 4, kAccelLsbPerG);
      putLe16(d, 25 + i * 4, -kAccelLsbPerG);
    }
    calibrated = true;
    break;
  }
  case 0x09: // pairing info: the MAC address
    size = 20;
    d[0] = 0x09;
    d[1] = 0x02;
    d[2] = 0x47;
    d[3] = 0x59;
    d[4] = 0x50;
    d[5] = macTail[0];
    d[6] = macTail[1];
    break;
  case 0x20: // firmware info
    size = 64;
    d[0] = 0x20;
    memcpy(&d[1], "Jan  1 2025", 11);
    memcpy(&d[12], "00:00:00", 8);
    putLe32(d, 24, 0x00000a0a); // hardware version
    putLe32(d, 28, 0x01000224); // firmware version
    break;
  default:
    reply.u.get_report_reply.err = EINVAL;
    break;
  }

  reply.u.get_report_reply.size = size;
  if (write(fd, &reply, sizeof(reply)) < 0) {
    // The device is going away; nothing left to answer.
  }
}

void DualSense::buildInputReport(uint8_t *out) {
  memset(out, 0, kInputReportSize);
  State s;
  int64_t motionAge;
  {
    std::lock_guard<std::mutex> lock(mutex);
    s = state;
    motionAge = nowUs() - lastMotionUs;
  }

  out[0] = 0x01;
  out[1] = s.lx;
  out[2] = s.ly;
  out[3] = s.rx;
  out[4] = s.ry;
  out[5] = s.l2;
  out[6] = s.r2;
  out[7] = seq++;
  out[8] = (s.buttons0 & 0xF0) | hatValue(s.dpadX, s.dpadY);
  out[9] = s.buttons1 | (s.l2 > 0 ? 0x04 : 0) | (s.r2 > 0 ? 0x08 : 0);
  out[10] = s.buttons2;

  bool fresh = motionAge < kMotionStaleUs;
  for (int i = 0; i < 3; i++) {
    putLe16(out, 16 + i * 2, fresh ? s.gyro[i] : 0);
    putLe16(out, 22 + i * 2, s.accel[i]);
  }
  // Sensor clock ticks at 3 MHz.
  putLe32(out, 28, (uint32_t)(nowUs() * 3));

  // Touchpad: both contacts released (bit 7 set), position zero.
  out[33] = 0x80;
  out[37] = 0x80;

  // Battery: full, on the cable.
  out[53] = (0x2 << 4) | 0xA;
}

void DualSense::sendReport() {
  uhid_event ev{};
  ev.type = UHID_INPUT2;
  ev.u.input2.size = kInputReportSize;
  buildInputReport(ev.u.input2.data);
  size_t len = offsetof(uhid_event, u.input2.data) + kInputReportSize;
  if (write(fd, &ev, len) < 0) {
    // Dropped report: the next tick resends the full state.
  }
}

void DualSense::setButton(const std::string &name, bool pressed) {
  uint8_t mask = 0;
  int group = -1;
  if (name == "X")           { group = 0; mask = 0x10; } // square
  else if (name == "A")      { group = 0; mask = 0x20; } // cross
  else if (name == "B")      { group = 0; mask = 0x40; } // circle
  else if (name == "Y")      { group = 0; mask = 0x80; } // triangle
  else if (name == "LB")     { group = 1; mask = 0x01; } // L1
  else if (name == "RB")     { group = 1; mask = 0x02; } // R1
  else if (name == "SELECT") { group = 1; mask = 0x10; } // create
  else if (name == "START")  { group = 1; mask = 0x20; } // options
  else if (name == "LS")     { group = 1; mask = 0x40; } // L3
  else if (name == "RS")     { group = 1; mask = 0x80; } // R3
  else if (name == "GUIDE")  { group = 2; mask = 0x01; } // PS
  if (group < 0) return;

  std::lock_guard<std::mutex> lock(mutex);
  uint8_t &field = group == 0   ? state.buttons0
                   : group == 1 ? state.buttons1
                                : state.buttons2;
  field = pressed ? (field | mask) : (field & ~mask);
}

void DualSense::setDpad(int x, int y) {
  std::lock_guard<std::mutex> lock(mutex);
  state.dpadX = x;
  state.dpadY = y;
}

void DualSense::setStick(int type, int x, int y) {
  std::lock_guard<std::mutex> lock(mutex);
  if (type == 0) {
    state.lx = stickByte(x);
    state.ly = stickByte(y);
  } else {
    state.rx = stickByte(x);
    state.ry = stickByte(y);
  }
}

void DualSense::setTrigger(int type, int value) {
  uint8_t v = (uint8_t)std::max(0, std::min(255, value));
  std::lock_guard<std::mutex> lock(mutex);
  (type == 0 ? state.l2 : state.r2) = v;
}

void DualSense::setMotion(int gx, int gy, int gz, int ax, int ay, int az) {
  std::lock_guard<std::mutex> lock(mutex);
  state.gyro[0] = clamp16((long long)gx * kGyroLsbPerDps / 1000);
  state.gyro[1] = clamp16((long long)gy * kGyroLsbPerDps / 1000);
  state.gyro[2] = clamp16((long long)gz * kGyroLsbPerDps / 1000);
  state.accel[0] = clamp16((long long)ax * kAccelLsbPerG / 1000);
  state.accel[1] = clamp16((long long)ay * kAccelLsbPerG / 1000);
  state.accel[2] = clamp16((long long)az * kAccelLsbPerG / 1000);
  lastMotionUs = nowUs();
}
