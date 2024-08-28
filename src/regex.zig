const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Error = error{ InvalidCharSet, InvalidCharSetClose, Unimplemented, NoRepeatElem } || Allocator.Error;

pub fn compile(alloc: Allocator, regex: []const u8) Error!Matcher {
    var lex = Lexer{
        .input = regex,
    };

    var seq = std.ArrayList(MatchItem).init(alloc);
    defer {
        for (seq.items) |*item| {
            item.deinit(alloc);
        }
        seq.deinit();
    }

    while (lex.next(.default)) |item| {
        switch (item) {
            .s => |s| try seq.append(.{ .contains = try alloc.dupe(u8, s) }),
            .sol => try seq.append(.sol),
            .eol => try seq.append(.eol),
            .repeat => {
                try applyRepeatElem(alloc, &seq, makeRepeat);
            },
            .optional => {
                try applyRepeatElem(alloc, &seq, makeOption);
            },
            .char_set_open => {
                const char_set = try consumeCharSet(&lex);
                try seq.append(.{ .char_set = try alloc.dupe(u8, char_set) });
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

pub const MatchBounds = struct {
    start: usize,
    end: usize,
};

pub const MatchIt = struct {
    s: []const u8,
    sequence: []MatchItem,
    // FIXME is matchbounds the right type? I dunno
    backtrack_ranges: std.ArrayList(MatchBounds),

    start_pos: usize = 0,
    string_pos: usize = 0,
    sequence_pos: usize = 0,

    match_bounds: ?std.ArrayList(MatchBounds) = null,

    pub fn deinit(self: *MatchIt) void {
        if (self.match_bounds) |*b| b.deinit();
        self.backtrack_ranges.deinit();
    }

    // If fails iterator is in invalid state
    pub fn step(self: *MatchIt) Error!?bool {
        if (self.start_pos >= self.s.len) {
            return false;
        }

        if (self.sequence_pos >= self.sequence.len) {
            return true;
        }

        const match_item = &self.sequence[self.sequence_pos];
        // matchera matcherb matcherc
        const match_range = try match_item.matchRange(self.s, self.string_pos) orelse {
            while (self.backtrack_ranges.items.len > 0) {
                const range = &self.backtrack_ranges.items[self.backtrack_ranges.items.len - 1];
                if (range.start == range.end) {
                    _ = self.backtrack_ranges.pop();

                    self.sequence_pos -= 1;

                    if (self.match_bounds) |*mb| {
                        _ = mb.pop();
                    }
                    continue;
                }

                range.end -= 1;
                self.string_pos = range.end;
                if (self.match_bounds) |*mb| {
                    mb.items[mb.items.len - 1].end = self.string_pos;
                }
                return null;
            }

            self.start_pos += 1;
            self.string_pos = self.start_pos;
            self.sequence_pos = 0;
            if (self.match_bounds) |*mb| mb.clearRetainingCapacity();
            return null;
        };

        const start = self.string_pos;
        try self.backtrack_ranges.append(.{
            .start = self.string_pos + match_range.min,
            .end = self.string_pos + match_range.max,
        });
        std.log.debug("{any}", .{self.backtrack_ranges.items});
        self.string_pos += match_range.max;

        if (self.match_bounds) |*match_bounds| {
            try match_bounds.append(.{
                .start = start,
                .end = self.string_pos,
            });
        }

        self.sequence_pos += 1;
        return null;
    }
};

pub const Matcher = struct {
    sequence: []MatchItem = &.{},

    pub fn deinit(self: *Matcher, alloc: Allocator) void {
        for (self.sequence) |*item| item.deinit(alloc);
        alloc.free(self.sequence);
    }

    pub fn matches(self: *const Matcher, alloc: Allocator, s: []const u8) Error!bool {
        var match_it = self.makeIt(alloc, s);
        defer match_it.deinit();

        while (true) {
            const ret = try match_it.step();
            return ret orelse continue;
        }
    }

    pub fn makeIt(self: *const Matcher, alloc: Allocator, s: []const u8) MatchIt {
        return MatchIt{
            .s = s,
            .sequence = self.sequence,
            .backtrack_ranges = std.ArrayList(MatchBounds).init(alloc),
        };
    }

    pub fn makeDebugIt(self: *const Matcher, alloc: Allocator, s: []const u8) MatchIt {
        var ret = self.makeIt(alloc, s);
        ret.match_bounds = std.ArrayList(MatchBounds).init(alloc);
        return ret;
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
        repeat,
        optional,
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
            '*' => return self.incAndReturn(.repeat),
            '?' => return self.incAndReturn(.optional),
            else => {},
        }

        return null;
    }

    fn findSpecialCharsDefault(self: *Lexer) ?usize {
        return std.mem.indexOfAny(u8, self.input, "^$[*?");
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
    repeat: *MatchItem,
    optional: *MatchItem,
    char_set: []const u8,

    pub fn deinit(self: *MatchItem, alloc: Allocator) void {
        switch (self.*) {
            .contains => |s| alloc.free(s),
            .char_set => |s| alloc.free(s),
            .sol, .eol => {},
            .optional => |item| {
                item.deinit(alloc);
                alloc.destroy(item);
            },
            .repeat => |item| {
                item.deinit(alloc);
                alloc.destroy(item);
            },
        }
    }

    // min/max match lengths
    const MatchRange = struct {
        min: usize,
        max: usize,

        fn fromCondAndLen(cond: bool, len: usize) ?MatchRange {
            if (cond) {
                return .{
                    .min = len,
                    .max = len,
                };
            } else {
                return null;
            }
        }
    };

    fn matchRange(self: *const MatchItem, line: []const u8, start_pos: usize) !?MatchRange {
        switch (self.*) {
            .contains => |s| {
                return MatchRange.fromCondAndLen(
                    start_pos < line.len and std.mem.startsWith(u8, line[start_pos..], s),
                    s.len,
                );
            },
            .sol => {
                return MatchRange.fromCondAndLen(
                    start_pos == 0,
                    0,
                );
            },
            .eol => {
                return MatchRange.fromCondAndLen(start_pos == line.len, 0);
            },
            .repeat => |m| {
                const first_range = (try m.matchRange(line, start_pos)) orelse return .{
                    .min = 0,
                    .max = 0,
                };
                var max = first_range.max;

                while (try m.matchRange(line, start_pos + max)) |range| {
                    max += range.max;
                }

                return .{
                    .min = 0,
                    .max = max,
                };
            },
            .optional => |m| {
                const inner_range = (try m.matchRange(line, start_pos)) orelse return .{
                    .min = 0,
                    .max = 0,
                };

                return .{
                    .min = 0,
                    .max = inner_range.max,
                };
            },
            .char_set => |set| {
                if (start_pos < line.len) {
                    for (set) |c| {
                        if (line[start_pos] == c) {
                            return .{
                                .min = 1,
                                .max = 1,
                            };
                        }
                    }

                    return null;
                } else {
                    return null;
                }
            },
        }
    }

    pub fn toString(self: *MatchItem, alloc: Allocator) ![]const u8 {
        return switch (self.*) {
            .contains => |s| try alloc.dupe(u8, s),
            .sol => try alloc.dupe(u8, "sol"),
            .eol => try alloc.dupe(u8, "eol"),
            .optional => |m| blk: {
                const inner = try m.toString(alloc);
                defer alloc.free(inner);
                break :blk try std.fmt.allocPrint(alloc, "optional({s})", .{inner});
            },
            .repeat => |m| blk: {
                const inner = try m.toString(alloc);
                defer alloc.free(inner);
                break :blk try std.fmt.allocPrint(alloc, "repeat({s})", .{inner});
            },
            .char_set => |s| try std.fmt.allocPrint(alloc, "[{s}]", .{s}),
        };
    }
};

const SplitContains = struct {
    first: []const u8,
    second: []const u8,

    pub fn deinit(self: *SplitContains, alloc: Allocator) void {
        alloc.free(self.first);
        alloc.free(self.second);
    }
};

fn splitLastChar(alloc: Allocator, s: []const u8) Error!SplitContains {
    const a = try alloc.alloc(u8, s.len - 1);
    @memcpy(a, s[0 .. s.len - 1]);

    const b = try alloc.alloc(u8, 1);
    b[0] = s[s.len - 1];

    return .{
        .first = a,
        .second = b,
    };
}

fn makeRepeat(item: *MatchItem) MatchItem {
    return .{ .repeat = item };
}

fn makeOption(item: *MatchItem) MatchItem {
    return .{ .optional = item };
}

fn applyRepeatElem(alloc: Allocator, seq: *std.ArrayList(MatchItem), f: fn (*MatchItem) MatchItem) !void {
    if (seq.items.len == 0) {
        return Error.NoRepeatElem;
    }

    var prev_elem = seq.pop();
    var keep_prev = false;
    defer {
        if (!keep_prev) {
            prev_elem.deinit(alloc);
        }
    }

    switch (prev_elem) {
        .sol, .eol => {
            return Error.NoRepeatElem;
        },
        .repeat => {
            return Error.NoRepeatElem;
        },
        .optional => {
            return Error.NoRepeatElem;
        },
        .contains => |s| {
            var split_contains = try splitLastChar(alloc, s);
            errdefer split_contains.deinit(alloc);

            const new_match = try alloc.create(MatchItem);
            errdefer alloc.destroy(new_match);

            new_match.* = .{ .contains = split_contains.second };

            try seq.append(.{
                .contains = split_contains.first,
            });

            try seq.append(f(new_match));
        },
        .char_set => |s| {
            keep_prev = true;

            const new_match = try alloc.create(MatchItem);
            errdefer alloc.destroy(new_match);

            new_match.* = .{ .char_set = s };

            try seq.append(f(new_match));
        },
    }
}

test "sol" {
    var matcher = try compile(std.testing.allocator, "^hello");
    defer matcher.deinit(std.testing.allocator);

    try std.testing.expectEqual(true, matcher.matches(std.testing.allocator, "hello"));
    try std.testing.expectEqual(true, matcher.matches(std.testing.allocator, "hello world"));
    try std.testing.expectEqual(false, matcher.matches(std.testing.allocator, "stuff before hello"));
    try std.testing.expectEqual(false, matcher.matches(std.testing.allocator, "goodbye"));
}

test "eol" {
    var matcher = try compile(std.testing.allocator, "again$");
    defer matcher.deinit(std.testing.allocator);

    try std.testing.expectEqual(false, matcher.matches(std.testing.allocator, "hello"));
    try std.testing.expectEqual(false, matcher.matches(std.testing.allocator, "goodbye"));
    try std.testing.expectEqual(false, matcher.matches(std.testing.allocator, "again hello"));
    try std.testing.expectEqual(true, matcher.matches(std.testing.allocator, "hello again"));
    try std.testing.expectEqual(true, matcher.matches(std.testing.allocator, "goodbye again"));
}

test "contains" {
    var matcher = try compile(std.testing.allocator, "again");
    defer matcher.deinit(std.testing.allocator);

    try std.testing.expectEqual(false, matcher.matches(std.testing.allocator, "hello"));
    try std.testing.expectEqual(false, matcher.matches(std.testing.allocator, "goodbye"));
    try std.testing.expectEqual(true, matcher.matches(std.testing.allocator, "hello again goodbye"));
    try std.testing.expectEqual(true, matcher.matches(std.testing.allocator, "hello again"));
    try std.testing.expectEqual(true, matcher.matches(std.testing.allocator, "goodbye again"));
}

test "char_set" {
    var matcher = try compile(std.testing.allocator, "he[lo][lo][lo]");
    defer matcher.deinit(std.testing.allocator);

    try std.testing.expectEqual(true, matcher.matches(std.testing.allocator, "hello"));
    try std.testing.expectEqual(true, matcher.matches(std.testing.allocator, "heooo"));
    try std.testing.expectEqual(true, matcher.matches(std.testing.allocator, "helll"));
    try std.testing.expectEqual(true, matcher.matches(std.testing.allocator, "heolo"));
    try std.testing.expectEqual(false, matcher.matches(std.testing.allocator, "heol"));
    try std.testing.expectEqual(false, matcher.matches(std.testing.allocator, "heola"));
}

test "wildcards" {
    var matcher = try compile(std.testing.allocator, "[ ][my]*yyy*yy little f*friend");
    defer matcher.deinit(std.testing.allocator);

    try std.testing.expectEqual(true, matcher.matches(std.testing.allocator, "hello myyyy little friend"));
    try std.testing.expectEqual(true, matcher.matches(std.testing.allocator, "hello myyyy little friend"));
    try std.testing.expectEqual(true, matcher.matches(std.testing.allocator, "hello myyyyyyy little fffriend"));
    try std.testing.expectEqual(false, matcher.matches(std.testing.allocator, "hello myyy little friend"));
}

test "optional" {
    var matcher = try compile(std.testing.allocator, "h?i mr?");
    defer matcher.deinit(std.testing.allocator);

    try std.testing.expectEqual(true, matcher.matches(std.testing.allocator, "hi mr"));
    try std.testing.expectEqual(true, matcher.matches(std.testing.allocator, "i m"));
    try std.testing.expectEqual(false, matcher.matches(std.testing.allocator, "hi"));
}
