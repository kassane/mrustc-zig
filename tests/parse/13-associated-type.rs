trait Iter { type Item; fn next(&mut self) -> Option<Self::Item>; }
