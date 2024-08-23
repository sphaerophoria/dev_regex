#include <linux/types.h>
#include <asm/ioctl.h>

#define REGEX_IOCTL_MAGIC 0xaa
#define REGEX_SET _IOW(REGEX_IOCTL_MAGIC, 0, char const*)

struct regex_set_arg {
    const char* data;
    // Len without null terminator
    __u64 len;
};

