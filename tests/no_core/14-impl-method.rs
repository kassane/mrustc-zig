#![allow(internal_features)]
#![feature(no_core, lang_items)]
#![no_core]
#[lang = "sized"] pub trait Sized {}
#[lang = "copy"]  pub trait Copy {}
struct S { v: i32 }
impl S { fn get(&self) -> i32 { self.v } }
