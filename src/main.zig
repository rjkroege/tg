// Convention: introduce imports here at the top. An @import returns a type.
const std = @import("std");
const clap = @import("clap");

// Convention: make some nice type package aliases here to save typing.
const debug = std.debug;
const io = std.io;

pub fn main() !void {
    // First we specify what parameters our program can take.
    // We can use `parseParamsComptime` to parse a string into an array of `Param(Help)`
    // The parse operation creates values in the Arguments corresponding to
    // the program command line flags from the text *at compile time*. Wow.
    // So let this sink in: this entire text is parsed at compile time and
    // builds a static data structure.
    const params = comptime clap.parseParamsComptime(
        \\-h, --help             Display this help and exit.
        \\-t, --tag <str>...  An option parameter which can be specified multiple times.
        \\<str>...
        \\
    );

    // Initialize our diagnostics, which can be used for reporting useful errors.
    // This is optional. You can also pass `.{}` to `clap.parse` if you don't
    // care about the extra information `Diagnostics` provides.
    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, clap.parsers.default, .{
        .diagnostic = &diag,
    }) catch |err| {
        // Report useful error and exit
        diag.report(io.getStdErr().writer(), err) catch {};
        return err;
    };
    defer res.deinit();

    if (res.args.help != 0)
        debug.print("--help\n", .{});
    for (res.args.tag) |s|
        debug.print("--tag = {s}\n", .{s});
    for (res.positionals) |pos|
        debug.print("{s}\n", .{pos});

    // This worked as I thought that it would. It displays the type of the tag setting.
    debug.print("{any}\n", .{@TypeOf(res.args.tag)});
}
