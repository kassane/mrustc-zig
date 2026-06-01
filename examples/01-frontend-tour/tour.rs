// tour.rs — a breadth-first tour of Rust syntax for mrustc's front-end.
//
// This file is fed through `mrustc … -Z stop-after=parse` by `zig build test`.
// The *parser* never loads an extern crate, so a single source file can
// exercise generics, traits, closures, pattern matching, macros-by-example and
// FFI declarations all at once. See docs/02-pipeline.md for the stage model.

use std::collections::HashMap;
use std::fmt::Debug;

/// A generic container with a trait bound and an associated function.
#[derive(Debug, Clone)]
pub struct Stack<T> {
    items: Vec<T>,
}

impl<T: Clone + Debug> Stack<T> {
    pub fn new() -> Self {
        Stack { items: Vec::new() }
    }
    pub fn push(&mut self, x: T) {
        self.items.push(x);
    }
    pub fn pop(&mut self) -> Option<T> {
        self.items.pop()
    }
}

/// A trait with a default method and an associated type.
trait Shape {
    type Unit;
    fn area(&self) -> Self::Unit;
    fn describe(&self) -> &'static str {
        "a shape"
    }
}

enum Geometry {
    Circle { r: f64 },
    Rect(f64, f64),
    Point,
}

fn classify(g: &Geometry) -> &'static str {
    match g {
        Geometry::Circle { r } if *r > 0.0 => "circle",
        Geometry::Rect(w, h) => if w == h { "square" } else { "rect" },
        Geometry::Point => "point",
        _ => "degenerate",
    }
}

// macro-by-example: variadic max
macro_rules! max {
    ($x:expr) => { $x };
    ($x:expr, $($rest:expr),+) => {{
        let a = $x;
        let b = max!($($rest),+);
        if a > b { a } else { b }
    }};
}

// FFI declaration: the C-ABI surface mrustc lowers to extern C symbols.
extern "C" {
    fn abs(x: i32) -> i32;
}

#[no_mangle]
pub extern "C" fn rs_add(a: i32, b: i32) -> i32 {
    a + b
}

fn main() {
    let mut s: Stack<i32> = Stack::new();
    for i in 0..5 {
        s.push(i * i);
    }
    let total: i32 = s.items.iter().filter(|&&x| x % 2 == 0).sum();
    let _ = max!(1, 2, 3, total);

    let table: HashMap<&str, Geometry> = HashMap::new();
    for (name, g) in &table {
        println!("{}: {}", name, classify(g));
    }

    let doubler = |x: i32| -> i32 { x * 2 };
    let _ = unsafe { abs(doubler(-3)) };
}
