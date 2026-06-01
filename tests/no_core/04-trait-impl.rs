#![allow(internal_features)]
#![feature(no_core, lang_items)]
#![no_core]
#[lang = "sized"] pub trait Sized {}
#[lang = "copy"]  pub trait Copy {}
trait T { fn m(&self) -> i32; }
struct S;
impl T for S { fn m(&self) -> i32 { 7 } }
