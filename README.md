# mrust-zig

Build [**mrustc**](https://github.com/thepowersgang/mrustc) (Mutabah's Rust
Compiler) and its `minicargo` companion with the **Zig build system** as the
C/C++ cross toolchain — the same approach as
[`ldc2-build.zig`](https://codeberg.org/kassane/ldc2-build.zig), but for a
project that needs no LLVM.

## Build

With any recent Zig (espressif bootstrap recommended):

```sh
zig build -Doptimize=ReleaseFast    # builds mrustc + minicargo into zig-out/bin
zig build run                       # runs `mrustc --version`
zig build minicargo                 # runs `minicargo --help`
zig build test                      # behaviour tests (see below)
```

## License

MIT (this packaging). `mrustc` is MIT-licensed upstream; zlib under the zlib
license.
