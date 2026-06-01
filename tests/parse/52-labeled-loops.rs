fn f() { 'outer: for _i in 0..3 { for _j in 0..3 { break 'outer; } } }
