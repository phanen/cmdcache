const std = @import("std");

fn fallback(allocator: std.mem.Allocator, args: []const []const u8) !void {
    const path = try findExeInPath(allocator, args[0]);
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

fn match_args(args: []const []const u8, pattern: []const []const u8) bool {
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
        .{ .pattern = &.{ "man", "-l" }, .handler = @import("./man.zig").man },
    };
    for (routes) |route| {
        if (match_args(args, route.pattern)) {
            return try route.handler(allocator, args);
        }
    }
    try fallback(allocator, args);
}

fn findExeInPath(allocator: std.mem.Allocator, exe_path: []const u8) ![:0]u8 {
    const exe_name = std.fs.path.basename(exe_path);
    const path = try std.fs.path.resolve(allocator, &.{exe_path});
    defer allocator.free(path);
    const path_env = std.posix.getenv("PATH") orelse return error.PathNotFound;
    var it = std.mem.splitAny(u8, path_env, ":");
    while (it.next()) |dir| {
        const candidate = try std.fs.path.join(allocator, &.{ dir, exe_name });
        if (std.mem.eql(u8, candidate, path)) continue;
        defer allocator.free(candidate);
        if (std.fs.cwd().access(candidate, .{})) |_| {
            // Make null-terminated string
            const nt = try allocator.allocSentinel(u8, candidate.len, 0);
            std.mem.copyForwards(u8, nt[0..candidate.len], candidate);
            return nt;
        } else |_| {}
    }
    return error.ExecutableNotFound;
}
