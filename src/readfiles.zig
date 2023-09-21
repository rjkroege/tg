const std = @import("std");

const debug = std.debug;
const expect = std.testing.expect;
const os = std.os;

// This is how to use a C program.
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
pub const Error = error{
    SystemResources,
    InvalidFileDescriptor,
    NameTooLong,
    TooBig,
    PermissionDenied,
    InputOutput,
    FileSystem,
    FileNotFound,
    NotDir,
} || std.os.UnexpectedError;

// Attempt at wrapping listxattr in a nice way.
pub fn listxattr(pheap: std.mem.Allocator, filename: []const u8) Error![][]const u8 {
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
    var buffy = lheap.alloc(u8, sz);

    while (true) {
        // TODO(rjk): Consider making the options configurable?
        const rc = c.listxattr(&posixpath, &buffy, buffy.len, 0);
        switch (errno(rc)) {
            .SUCCESS => return splitnamebuf(pheap, buffy[0..rc]),
            .ENOTSUP => unreachable,
            .ERANGE => {
                // buffy wasn't big enough
                sz *= 2;
                buffy = lheap.alloc(u8, sz);
                continue;
            },
            // TODO(rjk): Should it be error or Error?
            .EPERM => return error.PermissionDenied,
            .ENOTDIR => return Error.NotDir,
            .ENAMETOOLONG => return Error.NameTooLong,
            .EACCES => return Error.PermissionDenied,
            .ELOOP => return Error.SymLinkLoop,
            .EFAULT => return Error.SystemResources,
            .EIO => return Error.InputOutput,
            .EINVAL => unreachable,
            else => return Error.UnexpectedError,
        }
    }
}

const Allocator = std.mem.Allocator;

// Splits apart the namebuf by returning a vector of slices.
fn splitnamebuf(pheap: std.mem.Allocator, buffy: []const u8) Allocator.Error![][]const u8 {
    var list = std.ArrayList([]const u8).init(pheap);
    // I need this in because try can exit in an allocation error.
    defer list.deinit();

    debug.print("splitnamebuf at the top\n", .{});

    var si = std.mem.splitAny(u8, buffy, &[_]u8{0});
    while (si.next()) |s| {
        // Intuitively: I am leaking because I allocated the buffer from the lheap.
        if (s.len > 0) {
            var p = try pheap.alloc(u8, s.len);
            @memcpy(p, s);
            debug.print("appending {s}\n", .{s});
            try list.append(s);
        }
    }
    debug.print("splitnamebuf at the bottom\n", .{});
    return list.toOwnedSlice();
}

test "splitting works?" {
    // Note what happened here. I have allocated stuff above. I missed dealloc-ing everything.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const pheap = arena.allocator();

    debug.print("splitting test starts\n\n", .{});

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
// TODO(make an arena, print the names of stuff)
// TODO(rjk): add an arena... allocator: std.mem.Allocator
pub fn printStuffAboutAFile(filename: []const u8) !void {
    debug.print("printStuffAboutAFile {s}\n", .{filename});

    // TODO(rjk): Observe that this doesn't need to be a sentinel.
    var namebuf: [8000:0]u8 = undefined;
    const posixpath = try os.toPosixPath(filename);
    //const p : [*c]const u8 = @ptrCast(posixpath);
    const status = c.listxattr(&posixpath, &namebuf, namebuf.len, c.XATTR_NOFOLLOW);

    debug.print("{d}\n", .{status});
    if (status < 0) {
        return Error.UnexpectedError;
    }
    debug.print("error {s}\n", .{namebuf});

    // chop up...
    // iterate over a sentinel'ed string.
}
