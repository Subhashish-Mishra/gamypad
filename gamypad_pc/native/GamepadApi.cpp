#include "Gamepad.h"
#include "Motion.h"
#include "DualSense.h"
#include "LastError.h"

extern "C" {
    // Create a new Gamepad instance
    // Returns null on failure; Native_lastError() says why.
    Gamepad* Gamepad_new() {
        Gamepad* gp = new Gamepad();
        if (!gp->ok()) {
            delete gp;
            return nullptr;
        }
        return gp;
    }

    // Reason for the most recent null return from a *_new function.
    const char* Native_lastError() {
        return lastErrorRef().c_str();
    }

    // Delete a Gamepad instance
    void Gamepad_delete(Gamepad* gp) {
        delete gp;
    }

    // Press key
    void Gamepad_pressKey(Gamepad* gp, const char* key) {
        gp->pressKey(std::string(key));
    }

    // Release key
    void Gamepad_releaseKey(Gamepad* gp, const char* key) {
        gp->releaseKey(std::string(key));
    }

    // Set axis
    void Gamepad_setAxis(Gamepad* gp, int type, int valueX, int valueY) {
        gp->setAxis(type, valueX, valueY);
    }

    // set triggers
    void Gamepad_setTrigger(Gamepad* gp, int code, int value) {
        gp->setTrigger(code, value);
    }

    void Gamepad_setDpad(Gamepad* gp, int xValue, int yValue) {
        gp->setDpad(xValue, yValue);
    }

    // Motion sensors. Motion_new returns null when the device cannot be created.
    Motion* Motion_new() {
        Motion* m = new Motion();
        if (!m->ok()) {
            delete m;
            return nullptr;
        }
        return m;
    }

    void Motion_delete(Motion* m) {
        delete m;
    }

    void Motion_set(Motion* m, int gx, int gy, int gz, int ax, int ay, int az) {
        m->set(gx, gy, gz, ax, ay, az);
    }

    // DualSense (uhid). DualSense_new returns null on failure.
    DualSense* DualSense_new() {
        DualSense* ds = new DualSense();
        if (!ds->ok()) {
            delete ds;
            return nullptr;
        }
        return ds;
    }

    void DualSense_delete(DualSense* ds) {
        delete ds;
    }

    void DualSense_setButton(DualSense* ds, const char* name, int pressed) {
        ds->setButton(std::string(name), pressed != 0);
    }

    void DualSense_setDpad(DualSense* ds, int x, int y) {
        ds->setDpad(x, y);
    }

    void DualSense_setStick(DualSense* ds, int type, int x, int y) {
        ds->setStick(type, x, y);
    }

    void DualSense_setTrigger(DualSense* ds, int type, int value) {
        ds->setTrigger(type, value);
    }

    void DualSense_setMotion(DualSense* ds, int gx, int gy, int gz, int ax, int ay, int az) {
        ds->setMotion(gx, gy, gz, ax, ay, az);
    }

}