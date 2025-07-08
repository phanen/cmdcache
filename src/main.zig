const std = @import("std");
const utils = @import("./utils.zig");
const man = @import("./man.zig").man;

fn fallback(allocator: std.mem.Allocator, args: []const []const u8) !void {
    const path = try utils.findExeInPath(allocator, args[0]);
    defer allocator.free(path);
    const newargs = try std.process.argsAlloc(allocator);
    newargs[0] = path;
    const err = std.process.execv(allocator, newargs);
    const cmd = try std.mem.join(allocator, " ", newargs);
    std.process.fatal("the following command failed to execve with '{s}':\n{s}", .{ @errorName(err), cmd });
}

const ArgRouter = struct {
    pattern: []const []const u8,
    handler: *const fn (std.mem.Allocator, []const []const u8) anyerror!void,
};

fn match(args: []const []const u8, pattern: []const []const u8) bool {
    if (args.len < pattern.len) return false;
    for (pattern, 0..) |pat, i| {
        const a = if (i == 0) std.fs.path.basename(args[i]) else args[i];
        if (!std.mem.eql(u8, a, pat)) return false;
    }
    return true;
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    const routes = [_]ArgRouter{
        .{ .pattern = &.{ "man", "-l" }, .handler = man },
    };
    for (routes) |route| {
        if (match(args, route.pattern)) {
            return try route.handler(allocator, args);
        }
    }
    try fallback(allocator, args);
}
