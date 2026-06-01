mod inner { pub fn f() -> i32 { 1 } }
fn main() { let _ = inner::f(); }
