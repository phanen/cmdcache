const std = @import("std");
const mem = std.mem;

// NOTE: expand exe, ignore self
pub fn findExeInPath(allocator: mem.Allocator, exe: []const u8) ![:0]u8 {
    const exe_name = std.fs.path.basename(exe);
    const path_env = std.posix.getenv("PATH") orelse return error.PathEnvNotSet;
    const exe_self = try std.fs.selfExePathAlloc(allocator);
    defer allocator.free(exe_self);
    var it = mem.splitAny(u8, path_env, ":");
    while (it.next()) |dir| {
        const candidate = try std.fs.path.join(allocator, &.{ dir, exe_name });
        defer allocator.free(candidate);
        if (std.fs.cwd().access(candidate, .{})) |_| {
            const resolved = try std.fs.realpathAlloc(allocator, candidate);
            defer allocator.free(resolved);
            if (mem.eql(u8, resolved, exe_self)) continue;
            // Make null-terminated string
            const nt = try allocator.allocSentinel(u8, candidate.len, 0);
            mem.copyForwards(u8, nt[0..candidate.len], candidate);
            return nt;
        } else |_| {}
    }
    return error.ExecutableNotFound;
}
