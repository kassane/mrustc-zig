#![allow(internal_features)]
#![feature(no_core, lang_items)]
#![no_core]
#[lang = "sized"] pub trait Sized {}
#[lang = "copy"]  pub trait Copy {}
mod m { pub fn g() -> i32 { 1 } }
fn main() { let _ = m::g(); }
