#![allow(internal_features)]
#![feature(no_core, lang_items)]
#![no_core]
#[lang = "sized"] pub trait Sized {}
#[lang = "copy"]  pub trait Copy {}
struct P { x: i32, y: i32 }
fn main() { let p = P { x: 1, y: 2 }; let _ = p.x; }
