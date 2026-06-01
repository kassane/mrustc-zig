#![allow(internal_features)]
#![feature(no_core, lang_items)]
#![no_core]
#[lang = "sized"] pub trait Sized {}
#[lang = "copy"]  pub trait Copy {}
fn id<T>(x: T) -> T { x }
fn main() { let _ = id(5i32); }
