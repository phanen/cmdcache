//! Helpers for locating executables on disk.

const std = @import("std");

const assert = std.debug.assert;

/// PATH is at most `PATH_MAX` (4096 on Linux) bytes, so the number of `:`-separated
/// directories is bounded by that. 4096 entries is a generous safety bound.
const path_dir_count_max: usize = 4096;

/// Resolve `exe` to an absolute, null-terminated path by walking each directory
/// listed in `PATH`. The match against the current executable itself is skipped,
/// so a freshly-installed binary under `~/.local/bin` can shadow a copy already
/// sitting in `/usr/bin` without recursing into itself.
pub fn findExeInPath(
    io: std.Io,
    allocator: std.mem.Allocator,
    environ_map: *const std.process.Environ.Map,
    exe: []const u8,
) ![:0]u8 {
    const exe_name = std.fs.path.basename(exe);
    assert(exe_name.len > 0); // An empty basename can never be resolved.

    const path_env = environ_map.get("PATH") orelse return error.PathEnvNotSet;
    const exe_self = try std.process.executablePathAlloc(io, allocator);
    defer allocator.free(exe_self);

    const cwd = std.Io.Dir.cwd();
    var dir_index: usize = 0;
    var path_iter = std.mem.splitAny(u8, path_env, ":");
    while (path_iter.next()) |dir| : (dir_index += 1) {
        assert(dir_index < path_dir_count_max); // PATH overflow guard.

        const candidate = try std.fs.path.join(allocator, &.{ dir, exe_name });
        defer allocator.free(candidate);

        // `.{}` is `F_OK` here: we only need to know the file exists. Read/exec
        // checks belong to the caller, not to PATH lookup.
        if (cwd.access(io, candidate, .{})) |_| {
            const resolved = try cwd.realPathFileAlloc(io, candidate, allocator);
            defer allocator.free(resolved);
            if (std.mem.eql(u8, resolved, exe_self)) continue;

            // The child argv must be null-terminated; `realPathFileAlloc`
            // already is, but `candidate` is a plain slice so we add the
            // sentinel here.
            const nul_terminated = try allocator.allocSentinel(u8, candidate.len, 0);
            std.mem.copyForwards(u8, nul_terminated[0..candidate.len], candidate);
            return nul_terminated;
        } else |_| {}
    }
    return error.ExecutableNotFound;
}
