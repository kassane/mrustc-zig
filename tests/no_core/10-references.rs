#![allow(internal_features)]
#![feature(no_core, lang_items)]
#![no_core]
#[lang = "sized"] pub trait Sized {}
#[lang = "copy"]  pub trait Copy {}
fn f(x: &i32) -> i32 { *x }
fn main() { let v = 3; let _ = f(&v); }
