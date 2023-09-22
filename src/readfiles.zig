const std = @import("std");

const debug = std.debug;
const expect = std.testing.expect;
const os = std.os;

// This is how to use a C API.
const c = @cImport({
    // See https://github.com/ziglang/zig/issues/515
    @cDefine("_NO_CRT_STDIO_INLINE", "1");
    @cInclude("stdio.h");
    @cInclude("fcntl.h");
    @cInclude("sys/xattr.h");
});

// Print something with printf.
pub fn printSomethingWithC() void {
    _ = c.printf("c hello\n");
}

test "fooey" {
    try expect(100 == 100);
}

const errno = std.os.errno;

// Errors
pub const ReadfilesError = error{
    SystemResources,
    InvalidFileDescriptor,
    NameTooLong,
    TooBig,
    PermissionDenied,
    InputOutput,
    FileSystem,
    FileNotFound,
    NotDir,
    OutOfMemory,
    SymLinkLoop,
    UnexpectedError,
    IsDir,
    NoAttr,
} || std.os.UnexpectedError;

// Attempt at wrapping listxattr in a nice way.
pub fn listxattr(pheap: std.mem.Allocator, filename: []const u8) ReadfilesError![][:0]const u8 {
    // toPosixPath makes a Zig "string" into an array of chars for submission
    // to the kernel.
    const posixpath = try os.toPosixPath(filename);
    var buffy = std.ArrayList(u8).init(pheap);
    defer buffy.deinit();
    try buffy.resize(100);

    while (true) {
        // TODO(rjk): Consider making the options configurable?
        const rc = c.listxattr(&posixpath, buffy.items.ptr, buffy.items.len, 0);
        switch (errno(rc)) {
            .SUCCESS => {
                const ul: usize = @intCast(rc);
                try buffy.resize(ul);
                return splitnamebuf(pheap, try buffy.toOwnedSlice());
            },
            .OPNOTSUPP => unreachable,
            .RANGE => {
                try buffy.resize(buffy.items.len * 2);
                continue;
            },
            // TODO(rjk): It can be error. Or ReadfilesError as it's a member of that.
            .PERM => return error.PermissionDenied,
            .NOTDIR => return error.NotDir,
            .NAMETOOLONG => return error.NameTooLong,
            .ACCES => return error.PermissionDenied,
            .LOOP => return error.SymLinkLoop,
            .FAULT => return error.SystemResources,
            .IO => return error.InputOutput,
            .INVAL => unreachable,
            else => return error.UnexpectedError,
        }
    }
}

pub fn getxattr(pheap: std.mem.Allocator, filename: []const u8, key: [:0]const u8) ReadfilesError![]const u8 {
    const posixpath = try os.toPosixPath(filename);
    var buffy = std.ArrayList(u8).init(pheap);
    defer buffy.deinit();
    try buffy.resize(100);

    while (true) {
        // TODO(rjk): Consider making the options configurable?
        // TODO(rjk): Do something sensible with position?
        const rc = c.getxattr(&posixpath, key.ptr, buffy.items.ptr, buffy.items.len, 0, 0);
        switch (errno(rc)) {
            .SUCCESS => {
                const ul: usize = @intCast(rc);
                try buffy.resize(ul);
                return buffy.toOwnedSlice();
            },
            .NOATTR => return error.NoAttr,
            .OPNOTSUPP => unreachable,
            .RANGE => {
                try buffy.resize(buffy.items.len * 2);
                continue;
            },
            // TODO(rjk): It can be error. Or ReadfilesError as it's a member of that.
            .PERM => return error.PermissionDenied,
            .ISDIR => return error.IsDir,
            .NOTDIR => return error.NotDir,
            .NAMETOOLONG => return error.NameTooLong,
            .ACCES => return error.PermissionDenied,
            .LOOP => return error.SymLinkLoop,
            .FAULT => return error.SystemResources,
            .IO => return error.InputOutput,
            .INVAL => unreachable,
            else => return error.UnexpectedError,
        }
    }
}

const Allocator = std.mem.Allocator;

// Splits apart the namebuf by returning a vector of slices.
fn splitnamebuf(pheap: std.mem.Allocator, buffy: []const u8) Allocator.Error![][:0]const u8 {
    var list = std.ArrayList([:0]const u8).init(pheap);
    // I need this in because try can exit in an allocation error.
    defer list.deinit();

    // debug.print("splitnamebuf at the top\n", .{});

    var si = std.mem.splitAny(u8, buffy, &[_]u8{0});
    while (si.next()) |s| {
        // Intuitively: I am leaking because I allocated the buffer from the lheap.
        if (s.len > 0) {
            var p = try pheap.allocSentinel(u8, s.len, 0);
            @memcpy(p, s);
            // debug.print("appending {s}\n", .{s});
            try list.append(p);
        }
    }
    // debug.print("splitnamebuf at the bottom\n", .{});
    return list.toOwnedSlice();
}

test "splitting works?" {
    // Note what happened here. I made things complicated with two
    // allocators. The pheap also needs to be collected. I have been spoiled
    // by the use of GC.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const pheap = arena.allocator();

    const t0 = try splitnamebuf(pheap, "");
    debug.print("t0 {any} : {any} len {d}\n", .{ t0, @TypeOf(t0), t0.len });
    try expect(t0.len == 0);

    const t1 = try splitnamebuf(pheap, "foo");
    try expect(1 == t1.len);
    try std.testing.expectEqualStrings("foo", t1[0]);

    const t2 = try splitnamebuf(pheap, "foo\x00bar");
    try expect(2 == t2.len);
    try std.testing.expectEqualStrings("foo", t2[0]);
    try std.testing.expectEqualStrings("bar", t2[1]);

    const t3 = try splitnamebuf(pheap, "foo\x00bar\x00hello\x00");
    try expect(3 == t3.len);
    try std.testing.expectEqualStrings("foo", t3[0]);
    try std.testing.expectEqualStrings("bar", t3[1]);
    try std.testing.expectEqualStrings("hello", t3[2]);
}

// Called for each file.
pub fn printMetadatakeys(filename: []const u8) !void {
    // Initialize the arena.
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    // Free the memory on returning from this function.
    defer arena.deinit();

    const heap = arena.allocator();
    // debug.print("{any}\n", .{@TypeOf(heap)});

    if (listxattr(heap, filename)) |keys| {
        debug.print("{s}:", .{filename});
        for (keys) |k| {
            debug.print(" {s}", .{k});
        }
        debug.print("\n", .{});
        for (keys) |k| {
            const v = try getxattr(heap, filename, k);
            debug.print("    {s}:{s}\n", .{ k, v });
        }
    } else |err| {
        debug.print("{s}: can't read metadata: {any}\n", .{ filename, err });
    }
}
