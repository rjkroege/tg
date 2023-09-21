I decided to learn [Home ⚡ Zig Programming Language](https://ziglang.org/) and eschew Rust. I needed a Zig starter project. I wanted a way to read/write the metadata tags on files on MacOS. Hence `tg`: a simple
program to *tag*.

The purpose of this program is largely pedagogical. (I.e. I don't really know what I'm doing in this code.)
With it I learned:

* how to add a Zig package to an existing project by editing the `.zon` and `build.zig`
* how to use a C API from Zig
* how to wrap (maybe incorrectly) a C system call
* some thoughts on memory management and the passing of allocators.
* running tests not in the "root" source
* `build.zig` can also be debugged with printfs.

# Status

Shows the metadata keys on a list of files.