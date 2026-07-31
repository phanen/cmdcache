//! Dispatcher: routes the call to a specialized handler based on argv shape and the
//! environment. When no matcher fires, fall back to the real upstream command found
//! via `PATH`, replacing the current process image with it.

const std = @import("std");
const utils = @import("./utils.zig");
const man = @import("./man.zig").man;

const assert = std.debug.assert;

const Handler = *const fn (
    io: std.Io,
    arena: std.mem.Allocator,
    environ_map: *const std.process.Environ.Map,
    args: []const [:0]const u8,
) anyerror!void;

/// A pattern-based dispatch rule. `pattern[0]` is matched against the basename of
/// `args[0]`; later slots must match exactly. When `env_required` is set the matcher
/// is skipped unless that variable is present in the environment.
const Matcher = struct {
    pattern: []const []const u8,
    handler: Handler,
    env_required: ?[]const u8,

    pub fn match(
        self: *const Matcher,
        env_map: *const std.process.Environ.Map,
        args: []const [:0]const u8,
    ) bool {
        if (args.len < self.pattern.len) return false;
        if (self.env_required) |env_name| {
            if (env_map.get(env_name) == null) return false;
        }
        for (self.pattern, 0..) |pat, pattern_index| {
            const arg = if (pattern_index == 0)
                std.fs.path.basename(args[0])
            else
                args[pattern_index];
            if (!std.mem.eql(u8, arg, pat)) return false;
        }
        return true;
    }
};

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    assert(args.len >= 1); // argv[0] must always be present.

    const matchers = [_]Matcher{
        .{ .pattern = &.{ "man", "-l" }, .handler = man, .env_required = "VIMRUNTIME" },
    };
    for (matchers) |matcher| {
        if (matcher.match(init.environ_map, args)) {
            return try matcher.handler(init.io, arena, init.environ_map, args);
        }
    }
    try fallback(init.io, arena, init.environ_map, args);
}

/// Replace the current process with `args[0]` resolved through `PATH`, preserving
/// the rest of argv and the inherited environment.
fn fallback(
    io: std.Io,
    arena: std.mem.Allocator,
    environ_map: *const std.process.Environ.Map,
    args: []const [:0]const u8,
) !void {
    assert(args.len >= 1);
    const path = try utils.findExeInPath(io, arena, environ_map, args[0]);
    defer arena.free(path);

    const argv_buf = try arena.alloc([:0]const u8, args.len);
    argv_buf[0] = path;
    for (args[1..], 1..) |arg, argv_index| argv_buf[argv_index] = arg;

    return std.process.replace(io, .{ .argv = argv_buf, .environ_map = environ_map });
}
