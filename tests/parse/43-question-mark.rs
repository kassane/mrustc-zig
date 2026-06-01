fn f() -> Result<i32, ()> { let x: Result<i32,()> = Ok(1); Ok(x? + 1) }
