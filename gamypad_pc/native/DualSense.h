#pragma once

#include <atomic>
#include <cstdint>
#include <mutex>
#include <string>
#include <thread>

// A virtual Sony DualSense, created through /dev/uhid.
//
// Unlike uinput, uhid creates a real HID device: the kernel's hid-playstation
// driver binds to it and exposes the gamepad, motion sensors and touchpad, and
// a /dev/hidraw node appears — which is what WebHID, SDL and Steam read.
class DualSense {
public:
  // Check ok(); on failure lastErrorRef() says why.
  DualSense();
  ~DualSense();

  bool ok() const { return fd >= 0 && created; }

  void setButton(const std::string &name, bool pressed);
  // x: -1 left, 0 neutral, 1 right. y: -1 up, 0 neutral, 1 down.
  void setDpad(int x, int y);
  // type 0 = left stick, 1 = right. Wire units, -32767..32767.
  void setStick(int type, int x, int y);
  // type 0 = L2, 1 = R2. 0..255.
  void setTrigger(int type, int value);
  // Wire units: gyro in millidegrees/s, accelerometer in milli-g.
  void setMotion(int gx, int gy, int gz, int ax, int ay, int az);

private:
  struct State {
    uint8_t lx = 128, ly = 128, rx = 128, ry = 128;
    uint8_t l2 = 0, r2 = 0;
    uint8_t buttons0 = 0; // face buttons (hat is merged in at send time)
    uint8_t buttons1 = 0;
    uint8_t buttons2 = 0;
    int dpadX = 0, dpadY = 0;
    int16_t gyro[3] = {0, 0, 0};
    int16_t accel[3] = {0, 0, 0};
  };

  int fd = -1;
  bool created = false;
  std::thread worker;
  std::atomic<bool> running{false};
  std::atomic<bool> started{false};    // kernel sent UHID_START
  std::atomic<bool> calibrated{false}; // driver read the calibration report

  std::mutex mutex;
  State state;
  int64_t lastMotionUs = 0;
  uint8_t seq = 0;

  void loop();
  void sendReport();
  void answerFeature(uint32_t id, uint8_t reportNumber);
  void buildInputReport(uint8_t *out);
};
