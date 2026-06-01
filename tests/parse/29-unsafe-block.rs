fn f() { let p = &5 as *const i32; unsafe { let _ = *p; } }
