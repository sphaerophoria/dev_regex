const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Error = error{ InvalidCharSet, InvalidCharSetClose } || Allocator.Error;

pub fn compile(alloc: Allocator, regex: []const u8) Error!Matcher {
    var lex = Lexer{
        .input = regex,
    };

    var seq = std.ArrayList(MatchItem).init(alloc);
    defer seq.deinit();

    while (lex.next(.default)) |item| {
        switch (item) {
            .s => |s| try seq.append(.{ .contains = s }),
            .sol => try seq.append(.sol),
            .eol => try seq.append(.eol),
            .char_set_open => {
                const char_set = try consumeCharSet(&lex);
                try seq.append(.{ .char_set = char_set });
            },
            .char_set_close => {
                return Error.InvalidCharSetClose;
            },
        }
    }

    return .{
        .sequence = try seq.toOwnedSlice(),
    };
}

pub const Matcher = struct {
    sequence: []MatchItem = &.{},

    pub fn deinit(self: *Matcher, alloc: Allocator) void {
        alloc.free(self.sequence);
    }

    pub fn matches(self: *const Matcher, s: []const u8) bool {
        blk: for (0..s.len) |start_pos| {
            var string_pos: usize = start_pos;
            for (self.sequence) |match_item| {
                if (!match_item.startsWith(s, string_pos)) {
                    continue :blk;
                }
                string_pos += match_item.numBytes();
            }
            return true;
        }
        return false;
    }
};

fn consumeCharSet(lexer: *Lexer) Error![]const u8 {
    const s = lexer.next(.char_set) orelse return Error.InvalidCharSet;
    if (s != .s) {
        return Error.InvalidCharSet;
    }

    const close = lexer.next(.char_set) orelse return Error.InvalidCharSet;
    if (close != .char_set_close) {
        return Error.InvalidCharSet;
    }

    return s.s;
}

const Lexer = struct {
    input: []const u8,

    const Output = union(enum) {
        s: []const u8,
        sol,
        eol,
        char_set_open,
        char_set_close,
    };

    const ParserState = enum {
        default,
        char_set,
    };

    fn processSpecialCharDefault(self: *Lexer) ?Output {
        switch (self.input[0]) {
            '^' => return self.incAndReturn(.sol),
            '$' => return self.incAndReturn(.eol),
            '[' => return self.incAndReturn(.char_set_open),
            else => return null,
        }
    }

    fn findSpecialCharsDefault(self: *Lexer) ?usize {
        return std.mem.indexOfAny(u8, self.input, "^$[");
    }

    pub fn next(self: *Lexer, state: ParserState) ?Output {
        if (self.input.len == 0) {
            return null;
        }

        const special_ret = switch (state) {
            .default => self.processSpecialCharDefault(),
            .char_set => blk: {
                if (self.input[0] == ']') {
                    break :blk self.incAndReturn(.char_set_close);
                } else {
                    break :blk null;
                }
            },
        };

        if (special_ret) |output| {
            return output;
        }

        const next_special_pos = switch (state) {
            .default => self.findSpecialCharsDefault(),
            .char_set => std.mem.indexOfScalar(u8, self.input, ']'),
        };

        if (next_special_pos) |pos| {
            defer self.input = self.input[pos..];
            return .{ .s = self.input[0..pos] };
        } else {
            defer self.input = &.{};
            return .{ .s = self.input };
        }
    }

    fn incAndReturn(self: *Lexer, ret: Output) Output {
        if (self.input.len > 1) {
            self.input = self.input[1..];
        } else {
            self.input = &.{};
        }

        return ret;
    }
};

const MatchItem = union(enum) {
    contains: []const u8,
    sol,
    eol,
    char_set: []const u8,

    fn startsWith(self: *const MatchItem, line: []const u8, start_pos: usize) bool {
        switch (self.*) {
            .contains => |s| {
                if (start_pos < line.len) {
                    return std.mem.startsWith(u8, line[start_pos..], s);
                } else {
                    return false;
                }
            },
            .sol => {
                return start_pos == 0;
            },
            .eol => {
                return start_pos == line.len;
            },
            .char_set => |set| {
                if (start_pos < line.len) {
                    for (set) |c| {
                        if (line[start_pos] == c) {
                            return true;
                        }
                    }

                    return false;
                } else {
                    return false;
                }
            },
        }
    }

    fn numBytes(self: *const MatchItem) usize {
        switch (self.*) {
            .contains => |s| return s.len,
            .sol => return 0,
            .eol => return 1,
            .char_set => return 1,
        }
    }

    pub fn toString(self: *MatchItem, alloc: Allocator) ![]const u8 {
        return switch (self.*) {
            .contains => |s| try alloc.dupe(u8, s),
            .sol => try alloc.dupe(u8, "sol"),
            .eol => try alloc.dupe(u8, "eol"),
            .char_set => |s| try std.fmt.allocPrint(alloc, "[{s}]", .{s}),
        };
    }
};

test "sol" {
    var matcher = try compile(std.testing.allocator, "^hello");
    defer matcher.deinit(std.testing.allocator);

    try std.testing.expectEqual(true, matcher.matches("hello"));
    try std.testing.expectEqual(true, matcher.matches("hello world"));
    try std.testing.expectEqual(false, matcher.matches("stuff before hello"));
    try std.testing.expectEqual(false, matcher.matches("goodbye"));
}

test "eol" {
    var matcher = try compile(std.testing.allocator, "again$");
    defer matcher.deinit(std.testing.allocator);

    try std.testing.expectEqual(false, matcher.matches("hello"));
    try std.testing.expectEqual(false, matcher.matches("goodbye"));
    try std.testing.expectEqual(false, matcher.matches("again hello"));
    try std.testing.expectEqual(true, matcher.matches("hello again"));
    try std.testing.expectEqual(true, matcher.matches("goodbye again"));
}

test "contains" {
    var matcher = try compile(std.testing.allocator, "again");
    defer matcher.deinit(std.testing.allocator);

    try std.testing.expectEqual(false, matcher.matches("hello"));
    try std.testing.expectEqual(false, matcher.matches("goodbye"));
    try std.testing.expectEqual(true, matcher.matches("hello again goodbye"));
    try std.testing.expectEqual(true, matcher.matches("hello again"));
    try std.testing.expectEqual(true, matcher.matches("goodbye again"));
}

test "char_set" {
    var matcher = try compile(std.testing.allocator, "he[lo][lo][lo]");
    defer matcher.deinit(std.testing.allocator);

    try std.testing.expectEqual(true, matcher.matches("hello"));
    try std.testing.expectEqual(true, matcher.matches("heooo"));
    try std.testing.expectEqual(true, matcher.matches("helll"));
    try std.testing.expectEqual(true, matcher.matches("heolo"));
    try std.testing.expectEqual(false, matcher.matches("heol"));
    try std.testing.expectEqual(false, matcher.matches("heola"));
}
