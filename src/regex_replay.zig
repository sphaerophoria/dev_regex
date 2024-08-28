const std = @import("std");
const Allocator = std.mem.Allocator;
const regex = @import("regex.zig");

const RecordingItem = struct {
    string_pos: usize,
    matcher_state: [][2]usize,

    fn deinit(self: *RecordingItem, alloc: Allocator) void {
        alloc.free(self.matcher_state);
    }
};

const Recording = struct {
    input_string: []const u8,
    matchers: [][]const u8,
    items: []RecordingItem,

    pub fn deinit(self: *Recording, alloc: Allocator) void {
        for (self.items) |*item| {
            item.deinit(alloc);
        }

        alloc.free(self.items);
    }
};

const Args = struct {
    regex: []const u8,
    input: []const u8,
    output: []const u8,
    it: std.process.ArgIterator,

    pub fn parse(alloc: Allocator) !Args {
        var it = try std.process.argsWithAllocator(alloc);
        const process_name = it.next() orelse "regex_replay";

        const regex_arg = it.next() orelse {
            std.debug.print("no regex provided\n", .{});
            help(process_name);
        };

        const input = it.next() orelse {
            std.debug.print("no input provided\n", .{});
            help(process_name);
        };

        const output = it.next() orelse {
            std.debug.print("no output provided\n", .{});
            help(process_name);
        };

        return .{
            .regex = regex_arg,
            .input = input,
            .output = output,
            .it = it,
        };
    }

    pub fn deinit(self: *Args) void {
        self.it.deinit();
    }

    fn help(process_name: []const u8) noreturn {
        std.debug.print("Usage: {s} [regex] [input] [output]\n", .{process_name});
        std.process.exit(1);
    }
};

fn pushMatcherState(alloc: Allocator, match_it: *regex.MatchIt, recording_items: *std.ArrayList(RecordingItem)) !void {
    const match_bounds = match_it.match_bounds.?.items;
    const matcher_state = try alloc.alloc([2]usize, match_bounds.len);
    errdefer alloc.free(matcher_state);
    for (0..match_it.match_bounds.?.items.len) |i| {
        matcher_state[i][0] = match_bounds[i].start;
        matcher_state[i][1] = match_bounds[i].end;
    }

    try recording_items.append(.{
        .string_pos = match_it.string_pos,
        .matcher_state = matcher_state,
    });
}

fn runMatcher(alloc: Allocator, match_it: *regex.MatchIt, recording_items: *std.ArrayList(RecordingItem)) !bool {
    while (true) {
        const ret = (try match_it.step());

        try pushMatcherState(alloc, match_it, recording_items);

        if (ret == null) continue;
        return ret.?;
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const alloc = gpa.allocator();

    var args = try Args.parse(alloc);
    defer args.deinit();

    var matcher = try regex.compile(alloc, args.regex);
    defer matcher.deinit(alloc);

    var recording_items = std.ArrayList(RecordingItem).init(alloc);
    defer {
        for (recording_items.items) |*item| {
            item.deinit(alloc);
        }
        recording_items.deinit();
    }

    var match_it = matcher.makeDebugIt(alloc, args.input);
    defer match_it.deinit();

    try pushMatcherState(alloc, &match_it, &recording_items);
    if (runMatcher(alloc, &match_it, &recording_items)) |matched| {
        const match_s = if (matched) "matched" else "did not match";
        std.log.debug("\"{s}\" {s}", .{ args.input, match_s });
    } else |_| {
        std.log.err("Failed to run matcher", .{});
    }

    var matcher_names = try alloc.alloc([]const u8, match_it.sequence.len);
    @memset(matcher_names, &.{});
    defer {
        for (matcher_names) |name| {
            alloc.free(name);
        }
        alloc.free(matcher_names);
    }

    for (0..matcher_names.len) |i| {
        matcher_names[i] = try match_it.sequence[i].toString(alloc);
    }

    var recording = Recording{
        .items = try recording_items.toOwnedSlice(),
        .matchers = matcher_names,
        .input_string = args.input,
    };
    defer recording.deinit(alloc);

    const output = try std.fs.cwd().createFile(args.output, .{});
    try std.json.stringify(recording, .{
        .whitespace = .indent_2,
    }, output.writer());
}
