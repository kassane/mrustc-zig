fn classify(n: i32) -> &'static str { match n { 0 => "zero", 1..=9 => "small", _ => "big" } }
