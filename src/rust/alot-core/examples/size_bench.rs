// Times a point batch whose sizes are all distinct (R1.2's done-when: a
// plot mapping size to 1e4 values), cold and with the sprite cache warm.
//
//   cargo run --release -p alot-core --example size_bench
use alot_core::render::display::{DisplayList, Item};
use alot_core::render::points::{Point, PointBatch};
use alot_core::render::raster::{self, Options};
use std::time::Instant;

fn main() {
    let (w, h) = (1600usize, 1000usize);
    let mut seed = 42u64;
    let mut rnd = || {
        seed = seed.wrapping_mul(6364136223846793005).wrapping_add(1442695040888963407);
        (seed >> 11) as f64 / (1u64 << 53) as f64
    };
    // ggplot2's default size range (1-6 mm) as fontsize at 150 dpi.
    let pts: Vec<Point> = (0..10_000)
        .map(|_| Point {
            x: rnd() * w as f64,
            y: rnd() * h as f64,
            shape: 19,
            size: (1.0 + rnd() * 5.0) * 2.845276 * 150.0 / 72.0 + 0.5 * 3.7795 / 2.0 * 150.0 / 72.0,
            lwd: 0.5 * 3.7795 / 2.0 * 150.0 / 96.0,
            col: [0, 0, 0, 128],
            fill: [0, 0, 0, 128],
        })
        .collect();
    let mut out = vec![0u32; w * h];
    for i in 0..4 {
        let t = Instant::now();
        let mut list = DisplayList::new();
        list.push(Item::Points(PointBatch::new(&pts, 0)));
        let place = t.elapsed();
        raster::render_into(&list, w, h, &Options::default(), &mut out);
        println!("run {i}: place {:?}, total {:?}", place, t.elapsed());
    }
}
