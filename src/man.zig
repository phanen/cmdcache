const std = @import("std");
const utils = @import("./utils.zig");

pub fn man(allocator: std.mem.Allocator, args: []const []const u8) !void {
    const man_tar = args[2];
    const mtime = try getTimeStamp(man_tar);
    const cache_path = try getCachePath(allocator, man_tar, mtime);

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writerStreaming(&stdout_buffer);
    const stdout = &stdout_writer.interface;
    // check and read the cache
    if (std.fs.cwd().openFile(cache_path, .{}) catch null) |file| {
        defer file.close();
        var file_reader = file.reader(&.{});
        _ = try stdout.sendFileAll(&file_reader, .unlimited);
        try stdout.flush();
        return;
    }

    const man_exe = try utils.findExeInPath(allocator, args[0]);

    // run and write the cache
    var child = std.process.Child.init(&[_][]const u8{ man_exe, "-l", man_tar }, allocator);
    var envmap = try std.process.getEnvMap(allocator);
    defer envmap.deinit();
    try envmap.put("MANPAGER", "");
    child.env_map = &envmap;
    child.stdout_behavior = .Pipe;
    try child.spawn();
    var child_stdout = child.stdout.?.reader(&.{});

    var cache = try std.fs.cwd().createFile(cache_path, .{});
    defer cache.close();
    var tee_buf: [4096]u8 = undefined;
    while (true) {
        const n = try child_stdout.interface.readSliceShort(&tee_buf);
        if (n == 0) break;
        try stdout.writeAll(tee_buf[0..n]);
        try cache.writeAll(tee_buf[0..n]);
    }
    _ = try child.wait();
    return;
}

fn hexHash(comptime Hasher: anytype, in: []const u8, out: *[Hasher.digest_length * 2]u8) void {
    Hasher.hash(in, out[0..Hasher.digest_length], .{});
    const hex = std.fmt.bytesToHex(out[0..Hasher.digest_length], .upper);
    std.mem.copyForwards(u8, out, &hex);
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
    return try std.fmt.allocPrint(allocator, "{s}/{s}.{d}", .{ cache_dir, hash_buf[0..], mtime });
}
