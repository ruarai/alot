// Times sprite building and blending for a panel of the README plot.
use alot_core::render::points::{render, Point};
use std::time::Instant;

fn main() {
    let (w, h) = (470usize, 420usize);
    let mut seed = 42u64;
    let mut rnd = || {
        seed = seed.wrapping_mul(6364136223846793005).wrapping_add(1442695040888963407);
        (seed >> 11) as f64 / (1u64 << 53) as f64
    };
    let shapes = [16, 17, 15, 3];
    let pts: Vec<Point> = (0..166_667)
        .map(|_| Point {
            x: rnd() * w as f64,
            y: rnd() * h as f64,
            shape: shapes[(rnd() * 4.0) as usize],
            size: 10.86,
            lwd: 1.476,
            rgba: [(rnd() * 255.0) as u8, 100, 50, 76],
        })
        .collect();
    for _ in 0..3 {
        let t = Instant::now();
        render(w, h, pts[..10].iter().copied());
        let sprites = t.elapsed();
        let t = Instant::now();
        render(w, h, pts.iter().copied());
        println!("sprites only {:?}, full panel {:?}", sprites, t.elapsed());
    }
}
