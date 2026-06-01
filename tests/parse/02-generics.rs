fn id<T>(x: T) -> T { x }
fn main() { let _ = id::<i32>(5); }
