const std = @import("std");
const options = @import("build_options");

pub fn main(init: std.process.Init) !void {
    const alloc = init.gpa;

    // Collect all args into a flat slice (skip argv[0] = this exe)
    var orig: std.ArrayList([]const u8) = .empty;
    defer orig.deinit(alloc);
    var it = try init.minimal.args.iterateAllocator(alloc);
    defer it.deinit();
    _ = it.next(); // skip argv[0]
    while (it.next()) |a| try orig.append(alloc, a);

    // Launcher mode (cross-platform replacement for `env CC=... <prog>`):
    //   zig-cc --mrustc-run KEY=VALUE ... -- <program> <args...>
    // `zig build` uses this to spawn mrustc/minicargo with build-output paths
    // (CC, ZIGCC_EXTRA, MRUSTC_PATH) injected into the environment -- the maker
    // resolves those paths into the KEY=VALUE argv, since Run-step env vars must
    // be plain strings while the paths are LazyPaths. We export them here and exec
    // the real program with the augmented environment. mrustc later invokes us as
    // `$CC` without the sentinel, falling through to the compiler mode below.
    if (orig.items.len > 0 and std.mem.eql(u8, orig.items[0], "--mrustc-run")) {
        var j: usize = 1;
        while (j < orig.items.len and !std.mem.eql(u8, orig.items[j], "--")) : (j += 1) {
            const pair = orig.items[j];
            const eq = std.mem.indexOfScalar(u8, pair, '=') orelse continue;
            try init.environ_map.put(pair[0..eq], pair[eq + 1 ..]);
        }
        if (j >= orig.items.len) return error.MissingProgram; // no `--`
        const child_argv = orig.items[j + 1 ..]; // [program, args...]
        if (child_argv.len == 0) return error.MissingProgram;
        var child = try std.process.spawn(init.io, .{
            .argv = child_argv,
            .environ_map = init.environ_map,
        });
        const term = try child.wait(init.io);
        switch (term) {
            .exited => |code| std.process.exit(code),
            else => std.process.exit(1),
        }
    }

    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(alloc);
    try argv.append(alloc, options.zig_exe);
    try argv.append(alloc, "c++");

    var i: usize = 0;
    while (i < orig.items.len) : (i += 1) {
        const arg = orig.items[i];

        // Skip any existing -target args; we append our own below
        if (std.mem.eql(u8, arg, "-target")) {
            i += 1;
            continue;
        }

        // macOS cross: zig doesn't ship macOS framework TBD stubs (CoreFoundation,
        // libobjc, etc.). Strip explicit system framework/lib references and instead
        // use -undefined dynamic_lookup so all system symbols resolve at runtime
        // via the macOS dyld shared cache.
        if (options.triple) |triple| {
            const is_darwin = std.mem.indexOf(u8, triple, "macos") != null or
                std.mem.indexOf(u8, triple, "apple") != null;
            if (is_darwin) {
                // Strip -lobjc, -lSystem and similar macOS-only system libs
                if (std.mem.eql(u8, arg, "-lobjc") or
                    std.mem.eql(u8, arg, "-lSystem")) continue;
                // Strip "-framework <Name>" pairs (two-arg form)
                if (std.mem.eql(u8, arg, "-framework") and i + 1 < orig.items.len) {
                    i += 1;
                    continue;
                }
            }
        }

        // Strip ELF emulation / dynamic-linker flags incompatible with cross target.
        if (options.triple != null) {
            // -dynamic-linker /lib64/ld-linux-x86-64.so.2 (wrong arch)
            if (std.mem.eql(u8, arg, "-dynamic-linker")) {
                i += 1;
                continue;
            }
            // /lib/ld-* or /lib64/ld-* interpreter paths
            if ((std.mem.startsWith(u8, arg, "/lib") or
                std.mem.startsWith(u8, arg, "/usr/lib")) and
                std.mem.indexOf(u8, arg, "/ld-") != null)
                continue;
            // -m elf_x86_64 / -m armelf* / -m aarch64linux* linker emulation
            if (std.mem.eql(u8, arg, "-m") and i + 1 < orig.items.len) {
                const next = orig.items[i + 1];
                if (std.mem.startsWith(u8, next, "elf_") or
                    std.mem.startsWith(u8, next, "armelf") or
                    std.mem.startsWith(u8, next, "aarch64linux"))
                {
                    i += 1;
                    continue;
                }
            }
            // Strip target-specific -march=, -mabi=, -mcpu= flags; zig c++ derives
            // these from -target <triple> itself. Passing them separately can conflict
            // (e.g. -march=rv64gc is an arch string, not an LLVM CPU model name).
            if (std.mem.startsWith(u8, arg, "-march=") or
                std.mem.startsWith(u8, arg, "-mabi=") or
                std.mem.startsWith(u8, arg, "-mcpu="))
                continue;
        }

        // Strip --gc-sections unconditionally: lld's DW.ref.* handling differs from
        // GNU ld, causing D EH personality symbols to be dead-stripped when this
        // flag is present. zig c++ (lld) handles section GC internally without it.
        if (std.mem.eql(u8, arg, "-Wl,--gc-sections") or
            std.mem.eql(u8, arg, "--gc-sections") or
            std.mem.eql(u8, arg, "-Wl,-dead_strip") or
            std.mem.eql(u8, arg, "-dead_strip"))
            continue;

        try argv.append(alloc, arg);
    }

    // Append cross-compile target triple (clang style: -target <triple>)
    if (options.triple) |triple| {
        try argv.append(alloc, "-target");
        try argv.append(alloc, triple);
        // macOS cross: allow undefined symbols to resolve at runtime via dyld cache.
        // Required because we strip explicit framework/system-lib references above
        // (zig doesn't ship macOS SDK framework TBD stubs for cross-linking).
        if (std.mem.indexOf(u8, triple, "macos") != null or
            std.mem.indexOf(u8, triple, "apple") != null)
        {
            try argv.append(alloc, "-Wl,-undefined,dynamic_lookup");
        }
    }

    // Link any extra objects requested via $ZIGCC_EXTRA (delimited like $PATH:
    // ':' on POSIX, ';' on Windows). mrustc spawns us once for the final link of
    // its emitted C; this is how `zig build demo` threads a Zig-built object (e.g.
    // kernel.o exposing zig_triple) into that link without mrustc knowing about it.
    if (init.environ_map.get("ZIGCC_EXTRA")) |extra| {
        var parts = std.mem.tokenizeScalar(u8, extra, std.fs.path.delimiter);
        while (parts.next()) |obj| try argv.append(alloc, obj);
    }

    var child = try std.process.spawn(init.io, .{ .argv = argv.items });
    const term = try child.wait(init.io);
    switch (term) {
        .exited => |code| if (code != 0) std.process.exit(code),
        else => std.process.exit(1),
    }
}
