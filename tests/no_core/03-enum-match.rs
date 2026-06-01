#![allow(internal_features)]
#![feature(no_core, lang_items)]
#![no_core]
#[lang = "sized"] pub trait Sized {}
#[lang = "copy"]  pub trait Copy {}
enum E { A, B, C }
fn f(e: E) -> i32 { match e { E::A => 1, E::B => 2, E::C => 3 } }
