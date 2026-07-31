//! `man -l <file>` accelerator: serves the formatted page from
//! `$HOME/.cache/cmdcache/<md5(file)>.<mtime_ns>` when fresh, otherwise
//! re-runs the real `man` and snapshots its output. Only active when
//! `VIMRUNTIME` is set, to avoid masking the upstream pager in plain shells.

const std = @import("std");
const utils = @import("./utils.zig");

const assert = std.debug.assert;

/// Buffer size used for stdin/stdout/child pipe copies. 4 KiB matches the
/// common block size on Linux; large enough to amortize syscall overhead
/// without inflating stack usage.
const buffer_size: usize = 4096;

/// Hard upper bound on the number of tee iterations per cache miss.
/// At `buffer_size` bytes per chunk this caps a single run at 256 MiB,
/// which is generous for any man page while still failing fast on a
/// runaway child that never closes its stdout.
const tee_chunk_count_max: usize = 65_536;

pub fn man(
    io: std.Io,
    arena: std.mem.Allocator,
    environ_map: *const std.process.Environ.Map,
    args: []const [:0]const u8,
) !void {
    assert(args.len >= 3); // The matcher guarantees "man", "-l", "<file>".

    const man_tar = args[2];
    const cwd = std.Io.Dir.cwd();

    const paths = try cachePaths(io, arena, environ_map, man_tar);
    errdefer arena.free(paths.dir);
    errdefer arena.free(paths.file);

    if (try tryServeFromCache(io, cwd, paths.file)) return;

    try runAndCache(io, arena, cwd, environ_map, args[0], man_tar, paths);
}

/// Bundle of cache locations for a given man page. Both strings live in
/// `arena` and are freed together at the caller's scope exit.
const CachePaths = struct {
    dir: []const u8,
    file: []const u8,
};

/// Returns true and emits the cached output when the cache file is present.
/// Any error other than `FileNotFound` is propagated.
fn tryServeFromCache(io: std.Io, cwd: std.Io.Dir, cache_path: []const u8) !bool {
    const file = cwd.openFile(io, cache_path, .{ .mode = .read_only }) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => |e| return e,
    };
    defer file.close(io);

    var stdout_buffer: [buffer_size]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(io, &stdout_buffer);
    var file_reader = file.reader(io, &.{});
    _ = try stdout_writer.interface.sendFileAll(&file_reader, .unlimited);
    try stdout_writer.interface.flush();
    return true;
}

/// Spawns the real `man -l`, tees its stdout to the parent process and the
/// cache file. Ensures the child is reaped even if the tee loop bails early.
fn runAndCache(
    io: std.Io,
    arena: std.mem.Allocator,
    cwd: std.Io.Dir,
    environ_map: *const std.process.Environ.Map,
    man_arg0: [:0]const u8,
    man_tar: [:0]const u8,
    paths: CachePaths,
) !void {
    const man_exe = try utils.findExeInPath(io, arena, environ_map, man_arg0);

    // Inherit the parent environment, then blank MANPAGER so the upstream
    // man writes plain roff instead of opening a pager.
    var child_env = try environ_map.clone(arena);
    defer child_env.deinit();
    try child_env.put("MANPAGER", "");

    var child = try std.process.spawn(io, .{
        .argv = &[_][:0]const u8{ man_exe, "-l", man_tar },
        .environ_map = &child_env,
        .stdout = .pipe,
    });
    defer _ = child.wait(io) catch {}; // Always reap, even on tee overflow.

    // Only the miss path needs to create the cache directory; a hit proves
    // it already exists.
    try cwd.createDirPath(io, paths.dir);

    var child_stdout = child.stdout.?.reader(io, &.{});
    var cache = try cwd.createFile(io, paths.file, .{ .truncate = true });
    defer cache.close(io);

    var stdout_buffer: [buffer_size]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(io, &stdout_buffer);
    const stdout_iface = &stdout_writer.interface;

    var tee_buffer: [buffer_size]u8 = undefined;
    var chunk_index: usize = 0;
    while (chunk_index < tee_chunk_count_max) : (chunk_index += 1) {
        const bytes_read = try child_stdout.interface.readSliceShort(&tee_buffer);
        if (bytes_read == 0) break;
        const chunk = tee_buffer[0..bytes_read];
        try stdout_iface.writeAll(chunk);
        try cache.writeStreamingAll(io, chunk);
    } else {
        // Loop exited because the bound was reached, not because the child
        // closed its stdout. Treat as a hard error: leaving a partial cache
        // behind would mask the next miss with a stale snapshot.
        return error.StreamTooLong;
    }
    try stdout_iface.flush();
}

/// Compute the cache directory and file paths for `man_tar`. The mtime is
/// baked into the file name so a man page edit invalidates the cache
/// automatically without an extra stat call later.
fn cachePaths(
    io: std.Io,
    allocator: std.mem.Allocator,
    environ_map: *const std.process.Environ.Map,
    man_tar: []const u8,
) !CachePaths {
    const home = environ_map.get("HOME") orelse ".";
    const dir = try std.fmt.allocPrint(allocator, "{s}/.cache/cmdcache", .{home});

    var digest: [std.crypto.hash.Md5.digest_length]u8 = undefined;
    std.crypto.hash.Md5.hash(man_tar, &digest, .{});
    const hex: [digest.len * 2]u8 = std.fmt.bytesToHex(&digest, .upper);

    const stat = try std.Io.Dir.cwd().statFile(io, man_tar, .{});
    const mtime_ns = stat.mtime.nanoseconds;

    return .{
        .dir = dir,
        .file = try std.fmt.allocPrint(allocator, "{s}/{s}.{d}", .{ dir, &hex, mtime_ns }),
    };
}
