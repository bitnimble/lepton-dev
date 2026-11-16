// Virtual pad shaped like Steam Input's on a Deck ("Microsoft X-Box 360 pad N", 28de:11ff), so Lepton's
// gamepad passthrough treats it as one. Reads "key <code> <0|1>" / "abs <code> <value>" lines on stdin.
#include <fcntl.h>
#include <linux/uinput.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

static int fd;

static void emit(int type, int code, int value) {
    struct input_event ev = {.type = type, .code = code, .value = value};
    if (write(fd, &ev, sizeof ev) != sizeof ev) perror("write");
}

static void axis(int code, int min, int max) {
    struct uinput_abs_setup abs = {.code = code, .absinfo = {.minimum = min, .maximum = max}};
    ioctl(fd, UI_SET_ABSBIT, code);
    ioctl(fd, UI_ABS_SETUP, &abs);
}

int main(void) {
    static const int keys[] = {BTN_SOUTH, BTN_EAST, BTN_NORTH, BTN_WEST, BTN_TL, BTN_TR,
                               BTN_SELECT, BTN_START, BTN_MODE, BTN_THUMBL, BTN_THUMBR};
    fd = open("/dev/uinput", O_WRONLY | O_NONBLOCK);
    if (fd < 0) { perror("/dev/uinput"); return 1; }
    ioctl(fd, UI_SET_EVBIT, EV_KEY);
    ioctl(fd, UI_SET_EVBIT, EV_ABS);
    for (size_t i = 0; i < sizeof keys / sizeof keys[0]; i++) ioctl(fd, UI_SET_KEYBIT, keys[i]);
    axis(ABS_X, -32768, 32767);
    axis(ABS_Y, -32768, 32767);
    axis(ABS_RX, -32768, 32767);
    axis(ABS_RY, -32768, 32767);
    axis(ABS_Z, 0, 255);
    axis(ABS_RZ, 0, 255);
    axis(ABS_HAT0X, -1, 1);
    axis(ABS_HAT0Y, -1, 1);
    struct uinput_setup setup = {.id = {.bustype = BUS_USB, .vendor = 0x28de, .product = 0x11ff, .version = 1}};
    strcpy(setup.name, "Microsoft X-Box 360 pad 0");
    if (ioctl(fd, UI_DEV_SETUP, &setup) < 0 || ioctl(fd, UI_DEV_CREATE) < 0) { perror("create"); return 1; }

    char kind[8];
    int code, value;
    while (scanf("%7s %i %i", kind, &code, &value) == 3) {
        emit(strcmp(kind, "key") == 0 ? EV_KEY : EV_ABS, code, value);
        emit(EV_SYN, SYN_REPORT, 0);
    }
    ioctl(fd, UI_DEV_DESTROY);
    return 0;
}
