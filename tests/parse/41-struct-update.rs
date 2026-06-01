struct P { x: i32, y: i32, z: i32 }
fn f(p: P) -> P { P { x: 9, ..p } }
