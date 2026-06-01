// mini_core.rs — a hand-written minimal `libcore` that lets mrustc take a real
// Rust program all the way to a RUNNING binary, with `zig cc` as the C backend.
//
// Background: mrustc lowers Rust to C and shells out to $CC. The middle/back
// stages need libcore's "lang items" (operator traits, marker traits, the entry
// shim, …) and a few hardcoded paths (ops::RangeFull). Rather than bootstrap the
// full official libstd (270 MB source — see ../../docs/06-libcore.md and the
// `rustc-src` zon dependency), this file defines JUST the lang items mrustc
// requires for integer arithmetic, comparisons, control flow and FFI.
//
// Every item below was found empirically against mrustc rev be69c747 at
// MRUSTC_TARGET_VER=1.74 — each missing one aborts with
// "Undefined language item '<name>'". The operator-trait *bodies* are dead code:
// mrustc lowers `i32 + i32` to a builtin MIR BinOp, never a trait call
// (src/mir/from_hir.cpp), so the impls only have to EXIST to satisfy the bound.
//
// Build + run via `zig build test` / `zig build demo` (exit code is the computed
// result, 2 + 3*4 = 14). Equivalent by hand:
//   CC=<zig-cc-launcher> MRUSTC_TARGET_VER=1.74 mrustc mini_core.rs -o app && ./app; echo $?
// See ffi.rs for the Rust → Zig variant.

#![allow(internal_features)]
#![feature(no_core, lang_items)]
#![no_core]

// ---- marker traits the compiler/codegen resolve unconditionally at 1.74 -----
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

// ops::RangeFull: static_borrow_constants.cpp resolves this at setup via the
// `range_full` lang item, falling back to the hardcoded path ::<crate>::ops::
// RangeFull. We satisfy the fallback path so the pass finds it (hir.cpp:337).
pub mod ops { pub struct RangeFull; }

// A panic handler provides the `mrustc-panic_implementation` lang item.
struct PanicInfo;
#[panic_handler] fn panic(_: &PanicInfo) -> ! { loop {} }

// ---- arithmetic operator traits (+ impls for i32) ---------------------------
#[lang = "add"] trait Add<R = Self> { type Output; fn add(self, r: R) -> Self::Output; }
#[lang = "sub"] trait Sub<R = Self> { type Output; fn sub(self, r: R) -> Self::Output; }
#[lang = "mul"] trait Mul<R = Self> { type Output; fn mul(self, r: R) -> Self::Output; }
impl Add for i32 { type Output = i32; fn add(self, r: i32) -> i32 { self + r } }
impl Sub for i32 { type Output = i32; fn sub(self, r: i32) -> i32 { self - r } }
impl Mul for i32 { type Output = i32; fn mul(self, r: i32) -> i32 { self * r } }

// ---- comparison operator traits (+ impls for i32) ---------------------------
#[lang = "eq"]          trait PartialEq<R = Self>  { fn eq(&self, o: &R) -> bool; }
#[lang = "partial_ord"] trait PartialOrd<R = Self>: PartialEq<R> { fn lt(&self, o: &R) -> bool; }
impl PartialEq  for i32 { fn eq(&self, o: &i32) -> bool { *self == *o } }
impl PartialOrd for i32 { fn lt(&self, o: &i32) -> bool { *self <  *o } }

// ---- FFI: libc exit, so the process exit code carries the computed result ----
extern "C" { fn exit(code: i32); } // void exit(int) — ABI-correct, no `!` type

// ---- entry point ------------------------------------------------------------
// The C shim mrustc emits calls `start(main, argc, argv, sigpipe)`; lang_start
// must actually invoke `main()` (returning 0 ignores it and the program no-ops).
#[lang = "start"]
fn lang_start<T>(main: fn() -> T, _argc: isize, _argv: *const *const u8, _sigpipe: u8) -> isize {
    main();
    0
}
#[no_mangle] fn __libc_start_main() -> i32 { 0 }

fn main() {
    let a = 2 + 3 * 4;            // add + mul         -> 14
    let small = a < 10;          // partial_ord       -> bool (false)
    let result = if small { 0 } else { a };
    unsafe { exit(result); }     // process exit code  = 14
}
