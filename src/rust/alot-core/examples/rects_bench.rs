// Times a 1000 x 1000 tile layer (1e6 fill-only rects) on a 1600 x 1000
// page, as R1.3's done-when case: batch construction, then execution.
//
//   cargo run --release -p alot-core --example rects_bench
use alot_core::render::agg::Join;
use alot_core::render::display::{DisplayList, Item, Rect};
use alot_core::render::raster::{self, Options};
use alot_core::render::rects::{RectBatch, RectSpec, RectStyle};
use std::time::Instant;

fn main() {
    let (w, h) = (1600usize, 1000usize);
    let specs: Vec<RectSpec> = (0..1_000_000)
        .map(|k| {
            let (i, j) = ((k % 1000) as f64, (k / 1000) as f64);
            let c = (k * 2654435761usize % 255) as u8;
            RectSpec { x0: 20.0 + i * 1.55, y0: 10.0 + j * 0.97, x1: 20.0 + (i + 1.0) * 1.55, y1: 10.0 + (j + 1.0) * 0.97, fill: [c, 100, 200, 255], col: [0; 4], lwd: 0.0 }
        })
        .collect();
    let mut out = vec![0u32; w * h];
    let style = RectStyle { join: Join::Miter, mitre: 10.0, snap: true };
    for threads in [1, 8] {
        for _ in 0..3 {
            let t = Instant::now();
            let mut list = DisplayList::new();
            list.push(Item::PushClip(Rect { x0: 20.0, y0: 10.0, x1: 1570.0, y1: 980.0 }));
            list.push(Item::Rects(RectBatch::new(specs.clone(), style)));
            let built = t.elapsed();
            raster::render_into(&list, w, h, &Options { threads, ..Default::default() }, &mut out);
            println!("{threads} threads: batch {:?}, total {:?}", built, t.elapsed());
        }
    }
}
