// Times the band executor on a page: a white background plus 1e6 points
// (the README plot's symbol and alpha), with 1 and 8 threads (R1.1), and
// streams a 20 x 20 in page at 300 dpi to report peak memory.
//
//   cargo run --release -p alot-core --example points_bench
use alot_core::render::display::{DisplayList, Item};
use alot_core::render::points::{Point, PointBatch};
use alot_core::render::raster::{self, Options};
use std::time::Instant;

fn points(n: usize, w: f64, h: f64) -> Vec<Point> {
    let mut seed = 42u64;
    let mut rnd = || {
        seed = seed.wrapping_mul(6364136223846793005).wrapping_add(1442695040888963407);
        (seed >> 11) as f64 / (1u64 << 53) as f64
    };
    let shapes = [16, 17, 15, 3];
    (0..n)
        .map(|_| Point {
            x: rnd() * w,
            y: rnd() * h,
            shape: shapes[(rnd() * 4.0) as usize],
            size: 10.86,
            lwd: 1.476,
            rgba: [(rnd() * 255.0) as u8, 100, 50, 76],
        })
        .collect()
}

fn page(pts: &[Point]) -> DisplayList {
    let mut list = DisplayList::new();
    list.push(Item::Clear([255, 255, 255, 255]));
    list.push(Item::Points(PointBatch::new(pts.iter().copied())));
    list
}

fn peak_rss_mb() -> f64 {
    let s = std::fs::read_to_string("/proc/self/status").unwrap_or_default();
    s.lines()
        .find(|l| l.starts_with("VmHWM:"))
        .and_then(|l| l.split_whitespace().nth(1)?.parse::<f64>().ok())
        .map_or(f64::NAN, |kb| kb / 1024.0)
}

fn median(mut v: Vec<f64>) -> f64 {
    v.sort_by(|a, b| a.partial_cmp(b).unwrap());
    v[v.len() / 2]
}

fn main() {
    let (w, h) = (1600usize, 1000usize);
    let pts = points(1_000_000, w as f64, h as f64);
    let _ = page(&pts[..10]); // build the sprites
    let mut out = vec![0u32; w * h];
    for threads in [1, 2, 4, 8] {
        let opts = Options { threads, ..Default::default() };
        let mut prep = Vec::new();
        let mut exec = Vec::new();
        for _ in 0..7 {
            let t = Instant::now();
            let list = page(&pts);
            prep.push(t.elapsed().as_secs_f64() * 1e3);
            let t = Instant::now();
            raster::render_into(&list, w, h, &opts, &mut out);
            exec.push(t.elapsed().as_secs_f64() * 1e3);
        }
        println!("{threads} threads: place {:.1} ms, execute {:.1} ms (median of 7)", median(prep), median(exec));
    }
    drop(out);

    let (w, h) = (6000usize, 6000usize);
    let opts = Options { threads: 8, ..Default::default() };
    let list = page(&points(100_000, w as f64, h as f64));
    let before = peak_rss_mb();
    let t = Instant::now();
    let mut sum = 0u64;
    raster::execute(&list, w, h, &opts, |_, px| sum += px.len() as u64);
    println!(
        "20x20 in @300 dpi streamed in {:.0} ms: peak RSS {:.0} MB (before {:.0} MB); band bound {:.0} MB; a full f32 canvas would be {:.0} MB",
        t.elapsed().as_secs_f64() * 1e3,
        peak_rss_mb(),
        before,
        raster::band_memory(w, &opts) as f64 / 1048576.0,
        (w * h * 16) as f64 / 1048576.0
    );
    assert_eq!(sum, (w * h) as u64);
}
