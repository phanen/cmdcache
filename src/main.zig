const std = @import("std");

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len == 3 and std.mem.eql(u8, args[1], "-l")) {
        const man_path = args[2];
        const mtime = try getTimeStamp(man_path);
        const cache_path = try getCachePath(allocator, man_path, mtime);
        // check and read the cache
        if (std.fs.cwd().openFile(cache_path, .{}) catch null) |file| {
            defer file.close();
            var reader = file.reader();
            var writer = std.io.getStdOut().writer();
            var buf: [4096]u8 = undefined;
            while (true) {
                const n = try reader.read(&buf);
                if (n == 0) break;
                try writer.writeAll(buf[0..n]);
            }
            return;
        }

        // run and write the cache
        var child = std.process.Child.init(&[_][]const u8{ "man", "-l", man_path }, allocator);
        var envmap = try std.process.getEnvMap(allocator);
        defer envmap.deinit();
        try envmap.put("MANPAGER", "");
        child.env_map = &envmap;
        child.stdout_behavior = .Pipe;
        try child.spawn();

        var cache = try std.fs.cwd().createFile(cache_path, .{});
        defer cache.close();

        var stdout = child.stdout.?.reader();
        var out_writer = std.io.getStdOut().writer();
        var tee_buf: [4096]u8 = undefined;
        while (true) {
            const n = try stdout.read(&tee_buf);
            if (n == 0) break;
            try out_writer.writeAll(tee_buf[0..n]);
            try cache.writer().writeAll(tee_buf[0..n]);
        }
        _ = try child.wait();
        return;
    }

    const man_path = try findExeInPath(allocator, "man", args[0]);
    defer allocator.free(man_path);
    args[0] = man_path;
    const err = std.process.execv(allocator, args);
    const cmd = try std.mem.join(allocator, " ", args);
    std.process.fatal("the following command failed to execve with '{s}':\n{s}", .{ @errorName(err), cmd });
}

fn getTimeStamp(path: []const u8) !i128 {
    return (try std.fs.cwd().statFile(path)).mtime;
}

fn getCachePath(
    allocator: std.mem.Allocator,
    path: []const u8,
    mtime: i128,
) ![]u8 {
    const home = std.posix.getenv("HOME") orelse ".";
    const cache_dir = try std.fmt.allocPrint(allocator, "{s}/.cache/cmdcache", .{home});
    try std.fs.cwd().makePath(cache_dir);
    var hash_buf: [std.crypto.hash.Md5.digest_length * 2]u8 = undefined;
    hexHash(std.crypto.hash.Md5, path, &hash_buf);
    return try std.fmt.allocPrint(allocator, "{s}/{x}.{d}", .{ cache_dir, hash_buf[0..], mtime });
}

pub fn hexHash(comptime Hasher: anytype, in: []const u8, out: *[Hasher.digest_length * 2]u8) void {
    Hasher.hash(in, out[0..Hasher.digest_length], .{});
    const hex = std.fmt.bytesToHex(out[0..Hasher.digest_length], .upper);
    std.mem.copyForwards(u8, out, &hex);
}

fn findExeInPath(allocator: std.mem.Allocator, exe_name: []const u8, exclude: ?[]const u8) ![:0]u8 {
    const path_env = std.posix.getenv("PATH") orelse return error.PathNotFound;
    var it = std.mem.splitAny(u8, path_env, ":");
    while (it.next()) |dir| {
        const candidate = try std.fs.path.join(allocator, &.{ dir, exe_name });
        if (exclude) |ex| {
            if (std.mem.eql(u8, candidate, ex)) continue;
        }
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
