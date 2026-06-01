macro_rules! sum { ($($x:expr),*) => { 0 $(+ $x)* }; }
fn main() { let _ = sum!(1, 2, 3); }
