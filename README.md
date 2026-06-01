# mrust-zig

Build [**mrustc**](https://github.com/thepowersgang/mrustc) (Mutabah's Rust
Compiler) and its `minicargo` companion with the **Zig build system** as the
C/C++ cross toolchain.

## Build

- requires: Zig v0.16.0 or master

```sh
zig build -Doptimize=ReleaseFast    # builds mrustc + minicargo into zig-out/bin
zig build run                       # runs `mrustc --version`
zig build minicargo                 # runs `minicargo --help`
zig build test                      # behaviour tests (see below)
```

## License

[MIT](LICENSE) MIT lincense