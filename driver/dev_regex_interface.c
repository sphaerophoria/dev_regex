#include "dev_regex_ioctl.h"

#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/init.h>
#include <linux/fs.h>
#include <linux/cdev.h>
#include <asm/ioctl.h>

static struct cdev regex_cdev;
static struct class* regex_class;

// I'm not sure how correct this is, but it at the very least seems to solve our
// problems for now. Zig functions assume a 16 byte aligned stack, but the linux
// kernel uses 8 byte alignment. Wrap zig callbacks in this macro to ensure our
// stack is in a sane state
#define CALL_16_ALIGNED(__f)                                                     \
  ({                                                                             \
    int __x __attribute__((aligned(16))) = 0;                                    \
    /* Use __asm__ block to avoid optimizing away __x */                         \
    __asm__(""                                                                   \
            :                                                                    \
            : "g"(&__x) /* Tell GCC that __x needs to have an address so it is   \
                           forced onto the stack*/                               \
            : "memory" /* Tell GCC that memory could be changed                  \
			  by this asm block to avoid reordering */);             \
    __f; /* Actually do the work passed in */                                    \
  })

void* dev_regex_impl_alloc_file(void);
void dev_regex_impl_close(void*);
int64_t dev_regex_impl_write_file(void*, const char*, size_t);
int64_t dev_regex_impl_read_file(void*, char*, size_t);
int64_t dev_regex_impl_set_regex(void*, const char*, size_t);

void* dev_regex_alloc(size_t size) {
    return kzalloc(size, GFP_KERNEL);
}

void* dev_regex_realloc(void* p, size_t size) {
    return krealloc(p, size, GFP_KERNEL);
}

void dev_regex_free(void* p) {
    kfree(p);
}

uint64_t dev_regex_copy_from_user(void* to, const void *from, size_t size) {
    return copy_from_user(to, from, size);
}

uint64_t dev_regex_copy_to_user(void* to, const void *from, size_t size) {
    return copy_to_user(to, from, size);
}

static int regex_open(struct inode* inode, struct file* file) {
    file->private_data = CALL_16_ALIGNED(dev_regex_impl_alloc_file());
    if (file->private_data == NULL) {
        return -ENOMEM;
    }
    return 0;
}

static ssize_t regex_read(struct file * file, char __user * data, size_t size, loff_t * offs) {
    return CALL_16_ALIGNED(dev_regex_impl_read_file(file->private_data, data, size));
}

static ssize_t regex_write (struct file * file, const char __user * data, size_t size, loff_t * offs) {
    return CALL_16_ALIGNED(dev_regex_impl_write_file(file->private_data, data, size));
}

static int regex_release(struct inode * inode, struct file * file) {
    dev_regex_impl_close(file->private_data);
    return 0;
}

static long regex_ioctl(struct file * file, unsigned int cmd, unsigned long arg) {
    if (cmd != REGEX_SET) {
	return -EINVAL;
    }

    struct regex_set_arg regex_set_arg  = {
	.data = "hello\n",
	.len = 6,
    };

    unsigned long err = copy_from_user(&regex_set_arg, (struct regex_set_arg __user*)arg, sizeof(struct regex_set_arg));
    if (err != 0) {
        return err;
    }

    CALL_16_ALIGNED(dev_regex_impl_set_regex(file->private_data, regex_set_arg.data, regex_set_arg.len));

    return 0;
}

static struct file_operations regex_ops = {
    .owner = THIS_MODULE,
    .open = regex_open,
    .read = regex_read,
    .write = regex_write,
    .release = regex_release,
    .unlocked_ioctl = regex_ioctl,
};

#define REGEX_MAJOR 250
#define REGEX_MINOR 1
#define NUM_DEVS 1

static int __init dev_regex_start(void)
{
    int err = register_chrdev_region(MKDEV(REGEX_MAJOR, REGEX_MINOR), NUM_DEVS, "regex");
    if (err != 0) {
	return err;
    }
    cdev_init(&regex_cdev, &regex_ops);
    err = cdev_add(&regex_cdev, MKDEV(REGEX_MAJOR, REGEX_MINOR), NUM_DEVS);

    regex_class = class_create("regex_class");
    device_create(regex_class, NULL, MKDEV(REGEX_MAJOR, REGEX_MINOR), NULL, "regex");
    return 0;
}

static void __exit dev_regex_end(void)
{
    device_destroy(regex_class, MKDEV(REGEX_MAJOR, REGEX_MINOR));
    class_destroy(regex_class);
    cdev_del(&regex_cdev);
    unregister_chrdev_region(MKDEV(REGEX_MAJOR, REGEX_MINOR), NUM_DEVS);
}

module_init(dev_regex_start);
module_exit(dev_regex_end);

MODULE_LICENSE("GPL");
