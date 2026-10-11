#include <string>
#include <map>

using namespace std;

class Gamepad {
public:
    Gamepad();
    ~Gamepad();

    bool ok() const { return fd >= 0; }

    void pressKey(const string& key);
    void releaseKey(const string& key);
    void setAxis(int type, int valueX, int valueY);
    void setTrigger(int code, int value);
    void setDpad(int xValue, int yValue);
private:
    int fd = -1;
    std::map<string, int> keyMap;
    void emit(int type, int code, int value);
    void enableGamepad();
};
