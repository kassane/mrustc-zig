fn f(x: &mut i32) { *x += 1; }
fn main() { let mut v = 0; f(&mut v); }
