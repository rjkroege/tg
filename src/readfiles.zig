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

const SyscallError = error{
    Badness,
};

// TODO(rjk): hack this into something nicer.
// perhaps add some tests.
// yada

// Iterate over the files.
// TODO(rjk): add an arena... allocator: std.mem.Allocator
pub fn printStuffAboutAFile(filename: []const u8) !void {
        debug.print("printStuffAboutAFile {s}\n", .{filename});

	var namebuf: [8000:0]u8 = undefined;
	const posixpath = try os.toPosixPath(filename);
	//const p : [*c]const u8 = @ptrCast(posixpath);
	const status =  c.listxattr(&posixpath, &namebuf, namebuf.len, c.XATTR_NOFOLLOW);
	        
	debug.print("{d}\n", .{status});
	if (status < 0) {
		return SyscallError.Badness;
	} 
	debug.print("error {s}\n", .{namebuf});

// from the source... can do something sensible here.
//     while (true) {
//         const rc = open_sym(file_path, flags, perm);
//         switch (errno(rc)) {
//             .SUCCESS => return @as(fd_t, @intCast(rc)),
//             .INTR => continue,
// 
//             .FAULT => unreachable,
//             .INVAL => unreachable,
//             .ACCES => return error.AccessDenied,
//             .FBIG => return error.FileTooBig,
//             .OVERFLOW => return error.FileTooBig,
//             .ISDIR => return error.IsDir,
//             .LOOP => return error.SymLinkLoop,
//             .MFILE => return error.ProcessFdQuotaExceeded,
//             .NAMETOOLONG => return error.NameTooLong,
//             .NFILE => return error.SystemFdQuotaExceeded,
//             .NODEV => return error.NoDevice,
//             .NOENT => return error.FileNotFound,
//             .NOMEM => return error.SystemResources,
//             .NOSPC => return error.NoSpaceLeft,
//             .NOTDIR => return error.NotDir,
//             .PERM => return error.AccessDenied,
//             .EXIST => return error.PathAlreadyExists,
//             .BUSY => return error.DeviceBusy,
//             else => |err| return unexpectedErrno(err),
//         }
//     }
// }
// 

	// chop up...
	// iterate over a sentinel'ed string.
}
