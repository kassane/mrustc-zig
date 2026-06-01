#![allow(internal_features)]
#![feature(no_core, lang_items)]
#![no_core]
#[lang = "sized"] pub trait Sized {}
#[lang = "copy"]  pub trait Copy {}
struct W<T> { v: T }
fn main() { let _ = W { v: 3i32 }; }
