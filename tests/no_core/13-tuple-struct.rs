#![allow(internal_features)]
#![feature(no_core, lang_items)]
#![no_core]
#[lang = "sized"] pub trait Sized {}
#[lang = "copy"]  pub trait Copy {}
struct Pair(i32, i32);
fn main() { let p = Pair(1, 2); let _ = p.0; }
