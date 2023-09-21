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
} || std.os.UnexpectedError;

// Attempt at wrapping listxattr in a nice way.
pub fn listxattr(pheap: std.mem.Allocator, filename: []const u8) ReadfilesError![][]const u8 {
    // TODO(rjk): can arena be const?
    var arena = std.heap.ArenaAllocator.init(pheap);
    // Convention: I have two kinds of memory: the local heap and the
    // provided (parent) heap. I will (try!) to use the lheap for in-function
    // temporary space and objects escaping need to be allocated from the
    // pheap.

    // The arena is local (i.e. in-function) storage. The defer command here
    // will wipe all of the temp allocations out at the end of the frame.
    defer arena.deinit();
    const lheap = arena.allocator();

    // toPosixPath makes a Zig "string" into an array of chars for submission
    // to the kernel.
    const posixpath = try os.toPosixPath(filename);
    var sz: u32 = 200;
    var buffy = try lheap.alloc(u8, sz);

    while (true) {
        // TODO(rjk): Consider making the options configurable?
        const rc = c.listxattr(&posixpath, buffy.ptr, buffy.len, 0);
        switch (errno(rc)) {
            .SUCCESS => {
                const ul: usize = @intCast(rc);
                return splitnamebuf(pheap, buffy[0..ul]);
            },
            .OPNOTSUPP => unreachable,
            .RANGE => {
                // buffy wasn't big enough
                sz *= 2;
                buffy = try lheap.alloc(u8, sz);
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

const Allocator = std.mem.Allocator;

// Splits apart the namebuf by returning a vector of slices.
fn splitnamebuf(pheap: std.mem.Allocator, buffy: []const u8) Allocator.Error![][]const u8 {
    var list = std.ArrayList([]const u8).init(pheap);
    // I need this in because try can exit in an allocation error.
    defer list.deinit();

    // debug.print("splitnamebuf at the top\n", .{});

    var si = std.mem.splitAny(u8, buffy, &[_]u8{0});
    while (si.next()) |s| {
        // Intuitively: I am leaking because I allocated the buffer from the lheap.
        if (s.len > 0) {
            var p = try pheap.alloc(u8, s.len);
            @memcpy(p, s);
            // debug.print("appending {s}\n", .{s});
            try list.append(s);
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
    } else |err| {
        debug.print("{s}: can't read metadata: {any}\n", .{ filename, err });
    }
}
