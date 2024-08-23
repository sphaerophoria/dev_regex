const std = @import("std");
const Allocator = std.mem.Allocator;
const impl = @import("dev_regex_impl.zig");

pub const std_options = std.Options{
    .logFn = kernelLog,
};

export const __UNIQUE_ID_license250 linksection(".modinfo") = "license=GPL".*;

extern fn _printk(s: [*c]const u8, ...) c_int;

fn kernelPrint(comptime s: []const u8, args: anytype) void {
    var buf: [1024]u8 = undefined;
    const slice = std.fmt.bufPrint(&buf, s, args) catch &buf;
    _ = _printk("%.*s", slice.len, slice.ptr);
}

fn kernelLog(
    comptime message_level: std.log.Level,
    comptime scope: @TypeOf(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    _ = message_level;
    _ = scope;
    kernelPrint(format ++ "\n", args);
}

extern fn dev_regex_alloc(size: usize) ?*anyopaque;
extern fn dev_regex_realloc(p: ?*anyopaque, size: usize) ?*anyopaque;
extern fn dev_regex_free(p: ?*anyopaque) void;

fn kernelAlloc(ctx: *anyopaque, len: usize, ptr_align: u8, ret_addr: usize) ?[*]u8 {
    _ = ctx;
    _ = ptr_align;
    _ = ret_addr;
    const ret: ?[*]u8 = @ptrCast(@alignCast(dev_regex_alloc(len)));
    return ret;
}

fn kernelResize(ctx: *anyopaque, buf: []u8, buf_align: u8, new_len: usize, ret_addr: usize) bool {
    _ = ctx;
    _ = buf;
    _ = new_len;
    _ = buf_align;
    _ = ret_addr;
    return false;
}

fn kernelFree(ctx: *anyopaque, buf: []u8, buf_align: u8, ret_addr: usize) void {
    _ = ctx;
    _ = buf_align;
    _ = ret_addr;
    return dev_regex_free(buf.ptr);
}

var kernel_alloc_vtable: Allocator.VTable = .{
    .alloc = kernelAlloc,
    .resize = kernelResize,
    .free = kernelFree,
};

var kernel_alloc: Allocator = .{
    .ptr = undefined,
    .vtable = &kernel_alloc_vtable,
};

const LinuxError = struct {
    const EIO = 5;
    const ENOMEM = 12;
    const EINVAL = 22;
};

fn toLinuxError(err: impl.FileError) i32 {
    return switch (err) {
        impl.FileError.OutOfMemory => -LinuxError.ENOMEM,
        impl.FileError.InvalidCharSet => -LinuxError.EINVAL,
        impl.FileError.InvalidCharSetClose => -LinuxError.EINVAL,
        impl.FileError.UserIo => -LinuxError.EIO,
    };
}

pub export fn dev_regex_impl_alloc_file() ?*impl.File {
    const file = kernel_alloc.create(impl.File) catch return null;
    file.* = impl.File.init(kernel_alloc);
    return file;
}

pub export fn dev_regex_impl_close(file: *impl.File) void {
    file.deinit();
    kernel_alloc.destroy(file);
}

pub export fn dev_regex_impl_write_file(file: *impl.File, ptr: [*]u8, size: usize) i64 {
    const ret = file.write(ptr, size) catch |e| {
        return toLinuxError(e);
    };
    return @intCast(ret);
}
pub export fn dev_regex_impl_read_file(file: *impl.File, ptr: [*]u8, size: usize) i64 {
    const ret = file.read(ptr, size) catch |e| {
        return toLinuxError(e);
    };
    return @intCast(ret);
}

pub export fn dev_regex_impl_set_regex(file: *impl.File, data: [*]u8, len: usize) i64 {
    file.setRegex(kernel_alloc, data, len) catch |e| {
        return toLinuxError(e);
    };
    return 0;
}
