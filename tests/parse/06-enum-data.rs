enum Shape { Circle(f64), Rect { w: f64, h: f64 } }
fn f() -> Shape { Shape::Rect { w: 1.0, h: 2.0 } }
