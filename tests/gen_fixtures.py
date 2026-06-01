#!/usr/bin/env python3
"""Generate the mrust-zig Rust test fixtures (the data behind `zig build test`).

One file per case so each becomes its own named Run step in the build graph.
Fixtures are grouped by the deepest mrustc pipeline stage they are meant to
reach (see docs/02-pipeline.md):

  parse/      valid Rust syntax  -> `-Z stop-after=parse`   (exit 0)
  parse-fail/ malformed syntax   -> `-Z stop-after=parse`   (must abort)
  no_core/    `#![no_core]` items -> `-Z stop-after=expand` AND `=resolve` (exit 0)

Why the split: the *parser* never loads an extern crate, so parse fixtures may
freely mention `std`/`core`. Anything past `expand` loads the prelude crate, so
the deeper fixtures are `#![no_core]` (no libstd in the search path here). The
hard ceiling for a from-scratch `#![no_core]` crate in this mrustc revision is
`resolve`: `typeck` onward references real libcore lang items / `ops::RangeFull`
(hir.cpp:337), which only exist once libstd is bootstrapped (docs/02 §"Ceiling",
docs/04 §"Next steps"). Regenerate with:  python3 tests/gen_fixtures.py
"""
import os

HERE = os.path.dirname(os.path.abspath(__file__))

# --- parse stage: valid Rust syntax (exit 0 with -Z stop-after=parse) --------
PARSE = {
    "01-fn-arith": "fn main() { let _x: u32 = 1 + 2 * 3 - 4 / 2 % 3; }",
    "02-generics": "fn id<T>(x: T) -> T { x }\nfn main() { let _ = id::<i32>(5); }",
    "03-struct": "struct Point { x: i32, y: i32 }\nfn main() { let _p = Point { x: 1, y: 2 }; }",
    "04-tuple-struct": "struct Pair(i32, i32);\nfn main() { let _p = Pair(1, 2); }",
    "05-enum": "enum Color { Red, Green, Blue }\nfn main() { let _c = Color::Green; }",
    "06-enum-data": "enum Shape { Circle(f64), Rect { w: f64, h: f64 } }\nfn f() -> Shape { Shape::Rect { w: 1.0, h: 2.0 } }",
    "07-trait": "trait Greet { fn hello(&self) -> u32; }",
    "08-trait-default": "trait Greet { fn hello(&self) -> u32 { 42 } }",
    "09-impl": "struct S;\nimpl S { fn new() -> S { S } }",
    "10-impl-trait-for": "trait T { fn f(&self); }\nstruct S;\nimpl T for S { fn f(&self) {} }",
    "11-generic-struct": "struct Wrap<T> { inner: T }\nfn main() { let _w = Wrap { inner: 3i32 }; }",
    "12-where-clause": "fn f<T>(x: T) -> T where T: Clone { x.clone() }",
    "13-associated-type": "trait Iter { type Item; fn next(&mut self) -> Option<Self::Item>; }",
    "14-closure": "fn main() { let add = |a: i32, b: i32| a + b; let _ = add(1, 2); }",
    "15-closure-move": "fn main() { let v = 5; let f = move || v + 1; let _ = f(); }",
    "16-match": "fn classify(n: i32) -> &'static str { match n { 0 => \"zero\", 1..=9 => \"small\", _ => \"big\" } }",
    "17-match-binding": "fn f(o: Option<i32>) -> i32 { match o { Some(x) => x, None => 0 } }",
    "18-if-let": "fn f(o: Option<i32>) -> i32 { if let Some(x) = o { x } else { 0 } }",
    "19-while-let": "fn f(mut o: Option<i32>) { while let Some(_x) = o { o = None; } }",
    "20-loop-break-value": "fn f() -> i32 { let mut i = 0; loop { i += 1; if i > 3 { break i; } } }",
    "21-for-range": "fn f() { let mut s = 0; for i in 0..10 { s += i; } let _ = s; }",
    "22-lifetimes": "struct Ref<'a> { r: &'a i32 }\nfn longest<'a>(a: &'a str, b: &'a str) -> &'a str { if a.len() > b.len() { a } else { b } }",
    "23-references": "fn f(x: &mut i32) { *x += 1; }\nfn main() { let mut v = 0; f(&mut v); }",
    "24-slices-arrays": "fn f() { let a: [i32; 4] = [1, 2, 3, 4]; let _s: &[i32] = &a[1..3]; }",
    "25-vec-macro": "fn f() { let _v = vec![1, 2, 3]; }",
    "26-string": "fn f() { let s = String::from(\"hi\"); let _n = s.len(); }",
    "27-macro-rules": "macro_rules! sq { ($x:expr) => { $x * $x }; }\nfn main() { let _ = sq!(4); }",
    "28-macro-repeat": "macro_rules! sum { ($($x:expr),*) => { 0 $(+ $x)* }; }\nfn main() { let _ = sum!(1, 2, 3); }",
    "29-unsafe-block": "fn f() { let p = &5 as *const i32; unsafe { let _ = *p; } }",
    "30-extern-block": "extern \"C\" { fn abs(x: i32) -> i32; }",
    "31-extern-fn": "#[no_mangle]\npub extern \"C\" fn add(a: i32, b: i32) -> i32 { a + b }",
    "32-module": "mod inner { pub fn f() -> i32 { 1 } }\nfn main() { let _ = inner::f(); }",
    "33-use": "use std::collections::HashMap;\nfn f() { let _m: HashMap<i32, i32> = HashMap::new(); }",
    "34-const-static": "const MAX: u32 = 100;\nstatic NAME: &str = \"x\";\nfn main() { let _ = MAX; let _ = NAME; }",
    "35-generic-bounds": "fn print_all<T: std::fmt::Debug>(xs: &[T]) { for _x in xs {} }",
    "36-trait-objects": "trait Draw { fn draw(&self); }\nfn render(d: &dyn Draw) { d.draw(); }",
    "37-impl-trait-arg": "fn takes(_x: impl Clone) {}",
    "38-impl-trait-ret": "fn makes() -> impl Fn(i32) -> i32 { |x| x + 1 }",
    "39-nested-generics": "fn f() { let _v: Vec<Vec<Option<i32>>> = Vec::new(); }",
    "40-pattern-destructure": "fn f() { let (a, b) = (1, 2); let [c, d] = [3, 4]; let _ = a + b + c + d; }",
    "41-struct-update": "struct P { x: i32, y: i32, z: i32 }\nfn f(p: P) -> P { P { x: 9, ..p } }",
    "42-method-chain": "fn f() -> i32 { vec![1, 2, 3].iter().map(|x| x + 1).sum() }",
    "43-question-mark": "fn f() -> Result<i32, ()> { let x: Result<i32,()> = Ok(1); Ok(x? + 1) }",
    "44-derive": "#[derive(Clone, Copy, Debug, PartialEq)]\nstruct P { x: i32 }",
    "45-attributes": "#[inline]\nfn f() {}\n#[allow(dead_code)]\nstatic S: i32 = 0;",
    "46-const-generics": "struct Arr<const N: usize> { data: [i32; N] }",
    "47-type-alias": "type IntPair = (i32, i32);\nfn f() -> IntPair { (1, 2) }",
    "48-nested-fn": "fn outer() -> i32 { fn inner() -> i32 { 7 } inner() }",
    "49-raw-strings": "fn f() { let _s = r#\"a \"quoted\" path\\n\"#; }",
    "50-numeric-literals": "fn f() { let _ = (0xff, 0o17, 0b1010, 1_000_000u64, 3.14f32, 1e10f64); }",
    "51-shadowing": "fn f() { let x = 1; let x = x + 1; let x = x * 2; let _ = x; }",
    "52-labeled-loops": "fn f() { 'outer: for _i in 0..3 { for _j in 0..3 { break 'outer; } } }",
    "53-trait-generic-method": "trait Container { fn get<T: Default>(&self) -> T; }",
    "54-multi-trait-bound": "fn f<T: Clone + std::fmt::Debug + Send>(_x: T) {}",
    "55-fn-pointer": "fn apply(f: fn(i32) -> i32, x: i32) -> i32 { f(x) }",
}

# --- parse-fail: malformed syntax (mrustc aborts before parse completes) ------
PARSE_FAIL = {
    "01-missing-brace": "fn main() { let x = 1;",
    "02-bad-let": "fn main() { let = 5; }",
    "03-unclosed-string": "fn main() { let _s = \"oops; }",
    "04-double-arrow": "fn f() ->-> i32 { 1 }",
    "05-keyword-ident": "fn fn() {}",
    "06-stray-token": "fn main() { 1 + + ; }",
    "07-bad-struct": "struct S { x: , }",
    "08-unmatched-paren": "fn main() { foo(1, 2 ; }",
    "09-incomplete-match": "fn f(n: i32) { match n { 1 => } }",
    "10-bad-generic": "fn f<>>(x: i32) {}",
}

# --- no_core: `#![no_core]` crates that reach `expand` AND `resolve` ----------
# Deliberately avoid operators (`+`, `<`, `[]`, overloaded deref) and `std`
# macros: those need libcore lang items the crate doesn't define. The structural
# Rust below resolves cleanly with just `sized`/`copy`.
NO_CORE_PRELUDE = (
    '#![allow(internal_features)]\n'
    '#![feature(no_core, lang_items)]\n'
    '#![no_core]\n'
    '#[lang = "sized"] pub trait Sized {}\n'
    '#[lang = "copy"]  pub trait Copy {}\n'
)
NO_CORE = {
    "01-fn-call": "fn helper(x: i32) -> i32 { x }\nfn main() { let _ = helper(5); }",
    "02-struct-field": "struct P { x: i32, y: i32 }\nfn main() { let p = P { x: 1, y: 2 }; let _ = p.x; }",
    "03-enum-match": "enum E { A, B, C }\nfn f(e: E) -> i32 { match e { E::A => 1, E::B => 2, E::C => 3 } }",
    "04-trait-impl": "trait T { fn m(&self) -> i32; }\nstruct S;\nimpl T for S { fn m(&self) -> i32 { 7 } }",
    "05-generic-fn": "fn id<T>(x: T) -> T { x }\nfn main() { let _ = id(5i32); }",
    "06-generic-struct": "struct W<T> { v: T }\nfn main() { let _ = W { v: 3i32 }; }",
    "07-module-path": "mod m { pub fn g() -> i32 { 1 } }\nfn main() { let _ = m::g(); }",
    "08-type-alias": "type Int = i32;\nfn f(x: Int) -> Int { x }",
    "09-const": "const N: i32 = 10;\nfn main() { let _ = N; }",
    "10-references": "fn f(x: &i32) -> i32 { *x }\nfn main() { let v = 3; let _ = f(&v); }",
    "11-nested-fn": "fn outer() -> i32 { fn inner() -> i32 { 7 } inner() }",
    "12-trait-default": "trait T { fn d(&self) -> i32 { 42 } }",
    "13-tuple-struct": "struct Pair(i32, i32);\nfn main() { let p = Pair(1, 2); let _ = p.0; }",
    "14-impl-method": "struct S { v: i32 }\nimpl S { fn get(&self) -> i32 { self.v } }",
    "15-bool-if": "fn f(b: bool) -> i32 { if b { 1 } else { 0 } }",
}

def emit(d, sub, prefix=""):
    base = os.path.join(HERE, sub)
    os.makedirs(base, exist_ok=True)
    paths = []
    for name in sorted(d):
        text = prefix + d[name]
        if not text.endswith("\n"):
            text += "\n"
        with open(os.path.join(base, name + ".rs"), "w") as f:
            f.write(text)
        paths.append("tests/%s/%s.rs" % (sub, name))
    return paths


def zig_array(name, paths):
    lines = ["pub const %s = [_][]const u8{" % name]
    lines += ['    "%s",' % p for p in paths]
    lines.append("};")
    return "\n".join(lines)


parse = emit(PARSE, "parse")
parse_fail = emit(PARSE_FAIL, "parse-fail")
no_core = emit(NO_CORE, "no_core", NO_CORE_PRELUDE)

# build.zig @imports this name list rather than walking the filesystem, so the
# build works across Zig 0.15/0.16/0.17 (whose std.fs / std.Io APIs differ).
with open(os.path.join(HERE, "fixtures.zig"), "w") as f:
    f.write("// AUTO-GENERATED by tests/gen_fixtures.py -- do not edit by hand.\n")
    f.write("// Fixture path lists consumed by build.zig's `zig build test` harness.\n\n")
    f.write(zig_array("parse", parse) + "\n\n")
    f.write(zig_array("parse_fail", parse_fail) + "\n\n")
    f.write(zig_array("no_core", no_core) + "\n")

print("parse=%d parse-fail=%d no_core=%d (x2 stages) -> %d frontend cases"
      % (len(PARSE), len(PARSE_FAIL), len(NO_CORE),
         len(PARSE) + len(PARSE_FAIL) + 2 * len(NO_CORE)))
