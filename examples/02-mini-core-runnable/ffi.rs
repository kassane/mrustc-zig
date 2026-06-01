// ffi.rs — like mini_core.rs, but the computed value is sent THROUGH Zig.
//
// Rust (compiled by mrustc) calls `zig_triple`, a Zig `export fn` (kernel.zig),
// then exits with its result: 2+3*4 = 14, ×3 in Zig = 42. This is a genuine
// Rust ⇄ Zig FFI round-trip through the mrustc → C → `zig cc` toolchain (Zig is
// both the C backend AND the peer providing the symbol). `zig build demo` links
// kernel.o into mrustc's output via the zig-cc launcher's $ZIGCC_EXTRA. exit = 42.
//
// The lang-item prelude is identical to mini_core.rs (a `#![no_core]` crate must
// carry its own crate attributes, so `include!` of a shared prelude can't work —
// each file is a complete crate). See mini_core.rs for the per-item rationale.

#![allow(internal_features)]
#![feature(no_core, lang_items)]
#![no_core]

#[lang = "sized"]             trait Sized {}
#[lang = "copy"]              trait Copy {}
impl Copy for i32 {}
impl Copy for bool {}
#[lang = "unsize"]            trait Unsize<T> {}
#[lang = "coerce_unsized"]    trait CoerceUnsized<T> {}
#[lang = "fn_ptr_trait"]      trait FnPtr {}
#[lang = "discriminant_kind"] trait DiscriminantKind { type Discriminant; }
#[lang = "pointee_trait"]     trait Pointee { type Metadata; }
#[lang = "tuple_trait"]       trait Tuple {}
pub mod ops { pub struct RangeFull; }
struct PanicInfo;
#[panic_handler] fn panic(_: &PanicInfo) -> ! { loop {} }

#[lang = "add"] trait Add<R = Self> { type Output; fn add(self, r: R) -> Self::Output; }
#[lang = "mul"] trait Mul<R = Self> { type Output; fn mul(self, r: R) -> Self::Output; }
impl Add for i32 { type Output = i32; fn add(self, r: i32) -> i32 { self + r } }
impl Mul for i32 { type Output = i32; fn mul(self, r: i32) -> i32 { self * r } }

// imported from Zig (kernel.zig: `export fn zig_triple`) + libc `exit`.
extern "C" {
    fn zig_triple(x: i32) -> i32;
    fn exit(code: i32);
}

#[lang = "start"]
fn lang_start<T>(main: fn() -> T, _argc: isize, _argv: *const *const u8, _sigpipe: u8) -> isize {
    main();
    0
}
#[no_mangle] fn __libc_start_main() -> i32 { 0 }

fn main() {
    let a = 2 + 3 * 4;               // 14, computed by mrustc
    let z = unsafe { zig_triple(a) }; // Rust -> Zig: 14 * 3 = 42
    unsafe { exit(z); }              // process exit code = 42
}
