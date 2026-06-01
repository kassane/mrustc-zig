// use_real_core.rs — a `#![no_std]` program built against the OFFICIAL libcore
// (the one mrustc + `zig cc` produce from the `rustc-src` zon dependency, see
// docs/06-libcore.md and tools/build-libcore.sh).
//
// Unlike examples/03's mini_core.rs (which hand-defines the lang items), here
// `Option`, the operator impls and `PanicInfo` all come from the real libcore,
// loaded with `-L <dir-with-libcore.rlib>`. mrustc still needs the `start` lang
// item (it lives in libstd, not libcore) and a panic handler, which we provide.
//
//   mrustc use_real_core.rs -L <libcore-out> --crate-type bin -o app   (CC=zig cc)
//   ./app ; echo $?    ->    14
//
// Proof that the real official libcore goes through mrustc + zig cc end to end.

#![no_std]
#![feature(lang_items)]

use core::option::Option::{self, None, Some};

extern "C" {
    fn exit(code: i32);
}

#[lang = "start"]
fn lang_start<T>(main: fn() -> T, _argc: isize, _argv: *const *const u8, _sigpipe: u8) -> isize {
    main();
    0
}

fn main() {
    // Option + arithmetic operators are provided by the real libcore here.
    let v: Option<i32> = Some(2 + 3 * 4);
    let result = match v {
        Some(x) => x,
        None => 0,
    };
    unsafe { exit(result); } // process exit code = 14
}

#[panic_handler]
fn panic(_: &core::panic::PanicInfo) -> ! {
    loop {}
}
