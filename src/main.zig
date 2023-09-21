// Convention: introduce imports here at the top. An @import returns a type.
const std = @import("std");
const clap = @import("clap");

// Convention: make some nice type package aliases here to save typing.
const debug = std.debug;
const io = std.io;
const expect = std.testing.expect;

// Local imports. Every file is a module. The magic test stanza below
// will force the tests to be compiled.
const files = @import("readfiles.zig");

pub fn main() !void {
    // Use clap to process command line arguments. Some of this is moslty
    // copied from the clap example code.

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

    // This worked as I thought that it would. It displays the type of the
    // tag setting. This is very cool Zig feature. Preserved here to help
    // remind me of this feature.
    // debug.print("{any}\n", .{@TypeOf(res.args.tag)});
    // debug.print("{any}\n", .{@TypeOf(res.positionals)});

    if (res.args.help != 0)
        debug.print("--help\n", .{});
    for (res.args.tag) |s|
        debug.print("--tag = {s}\n", .{s});
    // TODO(rjk): Extend this to display the values for each key.
    for (res.positionals) |pos| {
        try files.printMetadatakeys(pos);
    }
}

test {
    // Magic stanza to force all the tests to run.
    // But also includes clap and that fails. (C.f. Nested Container Tests)
    // @import("std").testing.refAllDecls(@This());

    // Just refer to the container (in this case source file)
    _ = @import("readfiles.zig");
}
