// Virtual pad shaped like Steam Input's on a Deck ("Microsoft X-Box 360 pad N", 28de:11ff), so Lepton's
// gamepad passthrough treats it as one. Reads "key <code> <0|1>" / "abs <code> <value>" lines on stdin; logs
// rumble ("rumble <effect> <0|1>") on stderr.
#include <fcntl.h>
#include <linux/uinput.h>
#include <poll.h>
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

// Uploads and erases block the client until answered.
static void serve_ff(void) {
    struct input_event ev;
    while (read(fd, &ev, sizeof ev) == sizeof ev) {
        if (ev.type == EV_UINPUT && ev.code == UI_FF_UPLOAD) {
            struct uinput_ff_upload upload = {.request_id = ev.value};
            ioctl(fd, UI_BEGIN_FF_UPLOAD, &upload);
            upload.retval = 0;
            ioctl(fd, UI_END_FF_UPLOAD, &upload);
        } else if (ev.type == EV_UINPUT && ev.code == UI_FF_ERASE) {
            struct uinput_ff_erase erase = {.request_id = ev.value};
            ioctl(fd, UI_BEGIN_FF_ERASE, &erase);
            erase.retval = 0;
            ioctl(fd, UI_END_FF_ERASE, &erase);
        } else if (ev.type == EV_FF) {
            fprintf(stderr, "rumble %d %d\n", ev.code, ev.value);
        }
    }
}

int main(void) {
    static const int keys[] = {BTN_SOUTH, BTN_EAST, BTN_NORTH, BTN_WEST, BTN_TL, BTN_TR,
                               BTN_SELECT, BTN_START, BTN_MODE, BTN_THUMBL, BTN_THUMBR};
    fd = open("/dev/uinput", O_RDWR | O_NONBLOCK);
    if (fd < 0) { perror("/dev/uinput"); return 1; }
    ioctl(fd, UI_SET_EVBIT, EV_KEY);
    ioctl(fd, UI_SET_EVBIT, EV_ABS);
    ioctl(fd, UI_SET_EVBIT, EV_FF);
    ioctl(fd, UI_SET_FFBIT, FF_RUMBLE);
    for (size_t i = 0; i < sizeof keys / sizeof keys[0]; i++) ioctl(fd, UI_SET_KEYBIT, keys[i]);
    axis(ABS_X, -32768, 32767);
    axis(ABS_Y, -32768, 32767);
    axis(ABS_RX, -32768, 32767);
    axis(ABS_RY, -32768, 32767);
    axis(ABS_Z, 0, 255);
    axis(ABS_RZ, 0, 255);
    axis(ABS_HAT0X, -1, 1);
    axis(ABS_HAT0Y, -1, 1);
    struct uinput_setup setup = {
        .id = {.bustype = BUS_USB, .vendor = 0x28de, .product = 0x11ff, .version = 1}, .ff_effects_max = 16};
    strcpy(setup.name, "Microsoft X-Box 360 pad 0");
    if (ioctl(fd, UI_DEV_SETUP, &setup) < 0 || ioctl(fd, UI_DEV_CREATE) < 0) { perror("create"); return 1; }
    setvbuf(stderr, NULL, _IOLBF, 0);
    setvbuf(stdin, NULL, _IONBF, 0); // buffered lines would sit unseen by poll

    char line[64], kind[8];
    int code, value;
    struct pollfd fds[] = {{.fd = 0, .events = POLLIN}, {.fd = fd, .events = POLLIN}};
    while (poll(fds, 2, -1) >= 0) {
        if (fds[1].revents & POLLIN) serve_ff();
        if (!(fds[0].revents & (POLLIN | POLLHUP))) continue;
        if (!fgets(line, sizeof line, stdin)) break;
        if (sscanf(line, "%7s %i %i", kind, &code, &value) != 3) continue;
        emit(strcmp(kind, "key") == 0 ? EV_KEY : EV_ABS, code, value);
        emit(EV_SYN, SYN_REPORT, 0);
    }
    ioctl(fd, UI_DEV_DESTROY);
    return 0;
}
