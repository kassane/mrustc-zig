// kernel.zig — a Zig function exposed over the C ABI, called by ffi.rs.
// `export fn` gives the unmangled C symbol `zig_triple` that the mrustc-emitted
// C imports. Built as a `b.addObject`, linked into mrustc's output by `zig build demo`.
export fn zig_triple(x: i32) i32 {
    return x * 3;
}
