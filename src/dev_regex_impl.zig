const std = @import("std");
const Allocator = std.mem.Allocator;
const regex = @import("regex.zig");
const Matcher = regex.Matcher;

pub const FileError = error{UserIo} || regex.Error || Allocator.Error;

extern fn dev_regex_copy_from_user(to: ?*anyopaque, from: ?*anyopaque, size: usize) u64;
extern fn dev_regex_copy_to_user(to: ?*anyopaque, from: ?*anyopaque, size: usize) u64;

fn copyFromUser(to: ?*anyopaque, from: ?*anyopaque, size: usize) FileError!void {
    if (dev_regex_copy_from_user(to, from, size) != 0) {
        return FileError.UserIo;
    }
}

fn copyToUser(to: ?*anyopaque, from: ?*anyopaque, size: usize) FileError!void {
    if (dev_regex_copy_to_user(to, from, size) != 0) {
        return FileError.UserIo;
    }
}

pub const File = struct {
    alloc: Allocator,
    in_buf: std.ArrayListUnmanaged(u8),
    out_buf: std.ArrayListUnmanaged(u8),
    matcher: ?Matcher,

    pub fn init(alloc: Allocator) File {
        return .{
            .alloc = alloc,
            .in_buf = .{},
            .out_buf = .{},
            .matcher = null,
        };
    }

    pub fn deinit(self: *File) void {
        self.in_buf.deinit(self.alloc);
        self.out_buf.deinit(self.alloc);
        if (self.matcher) |*m| m.deinit(self.alloc);
    }

    pub fn write(self: *File, ptr: [*]u8, size: usize) FileError!u64 {
        try self.in_buf.ensureUnusedCapacity(self.alloc, size);

        const old_len = self.in_buf.items.len;
        self.in_buf.items.len = self.in_buf.items.len + size;
        const out = self.in_buf.items.ptr + old_len;
        _ = dev_regex_copy_from_user(out, ptr, size);

        return size;
    }

    pub fn read(self: *File, ptr: [*]u8, size: usize) FileError!u64 {
        if (self.out_buf.items.len != 0) {
            return self.readOutputBuf(ptr, size);
        }

        while (std.mem.indexOfScalar(u8, self.in_buf.items, 10)) |newline_pos| {
            const next_in_line = self.in_buf.items[0..newline_pos];

            if (self.matcher) |matcher| {
                if (try matcher.matches(self.alloc, next_in_line)) {
                    try self.out_buf.appendSlice(self.alloc, next_in_line);
                    try shiftBuf(self.alloc, &self.in_buf, next_in_line.len + 1);
                    return self.readOutputBuf(ptr, size);
                } else {
                    try shiftBuf(self.alloc, &self.in_buf, next_in_line.len + 1);
                }
            } else {
                return 0;
            }
        }

        return 0;
    }

    pub fn setRegex(self: *File, alloc: Allocator, data: [*]u8, len: usize) FileError!void {
        const buf = try alloc.alloc(u8, len);
        // FIXME: This leaks for sure right? Regex compile depends on this, but
        // when file is closed we never free this cause it's lost
        errdefer alloc.free(buf);

        try copyFromUser(buf.ptr, data, len);

        self.matcher = try regex.compile(alloc, buf);
        errdefer self.matcher.?.deinit(alloc);
    }

    fn readOutputBuf(self: *File, ptr: [*]u8, size: usize) FileError!u64 {
        const copy_len = @min(size, self.out_buf.items.len);
        try copyToUser(ptr, self.out_buf.items.ptr, copy_len);
        try shiftBuf(self.alloc, &self.out_buf, copy_len);
        return copy_len;
    }
};

fn shiftBuf(alloc: Allocator, buf: *std.ArrayListUnmanaged(u8), amount: usize) Allocator.Error!void {
    std.mem.copyForwards(u8, buf.items, buf.items[amount..]);
    try buf.resize(alloc, buf.items.len - amount);
}
