# examples — mrustc, driven by Zig

Source crates that show what the Zig-built **mrustc** can do, each exercised by a
`zig build` step (no standalone shell scripts — the build graph runs them):

| source | what it shows | build step |
|--------|---------------|------------|
| [`01-frontend-tour/tour.rs`](01-frontend-tour/tour.rs) | mrustc as a Rust **front-end**: lexing/parsing generics, traits, closures, macro-by-example, FFI decls in one crate | `zig build test` (parse) |
| [`02-mini-core-runnable/mini_core.rs`](02-mini-core-runnable/mini_core.rs) | `Rust → C → running binary`: a hand-written minimal libcore lets mrustc compile `2 + 3*4` to a native binary via `zig cc` → exit **14** | `zig build test` / `demo` |
| [`02-mini-core-runnable/ffi.rs`](02-mini-core-runnable/ffi.rs) + [`kernel.zig`](02-mini-core-runnable/kernel.zig) | **Rust ⇄ Zig FFI** through the toolchain: mrustc-compiled Rust calls a Zig `export fn`; `zig_triple(14)` → exit **42** | `zig build demo` |
| [`02-mini-core-runnable/use_real_core.rs`](02-mini-core-runnable/use_real_core.rs) | a `#![no_std]` program against the **official** libcore (built by mrustc + `zig cc` from the `rustc-src` dependency) → exit **14** | `zig build -Dlibcore -Drustc-src=<dir> libcore` |

## The big picture

```
        Rust source ──mrustc──▶ C source ──$CC=zig cc──▶ running binary
       (AST → HIR → MIR)                    (Zig = C backend + FFI peer)
```

mrustc lowers Rust to **C** and shells out to whatever `$CC` names
(`src/trans/codegen_c.cpp`). With `zig cc` as `$CC`, Zig is both the code
generator and a first-class FFI peer:

- a Rust `#[no_mangle] pub extern "C" fn rs_x(..)` becomes a C symbol Zig can
  `extern fn rs_x(..)`;
- a Rust `extern "C" { fn zig_y(..); }` resolves against a Zig `export fn zig_y(..)`.


```sh
zig build test            # parse/expand/resolve suite + the mini-libcore codegen (exit 14)
zig build demo            # mini_core (14) + the Rust → Zig FFI (42)
zig build -Dlibcore -Drustc-src=<dir> libcore   # build the official libcore + a program against it
```
