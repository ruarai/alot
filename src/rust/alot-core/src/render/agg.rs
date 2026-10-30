//! Ports of the Anti-Grain Geometry pieces ragg draws marks with (ragg
//! 1.5.2 src/agg), so coverage matches ragg's exactly:
//!
//! - the exact-area scanline rasteriser (`rasterizer_cells_aa::line` and
//!   `render_hline` in agg_rasterizer_cells_aa.h; `calculate_alpha` and
//!   `sweep_scanline` in agg_rasterizer_scanline_aa.h), non-zero rule, no
//!   gamma. Coordinates are 24.8 fixed point (`poly_subpixel_shift` 8).
//!   Cells are summed densely over the shape's bounding box; AGG sums cells
//!   with the same x when sweeping, so the alpha is the same.
//! - the stroker (`vcgen_stroke`, agg_vcgen_stroke.cpp; `math_stroke`,
//!   agg_math_stroke.h) with AGG's defaults (`inner_miter`, approximation
//!   scale 1);
//! - `ellipse` vertices (agg_ellipse.h).

const SHIFT: i32 = 8;
const SCALE: i32 = 1 << SHIFT;
const MASK: i32 = SCALE - 1;
const VERTEX_DIST_EPSILON: f64 = 1e-14;
const INTERSECTION_EPSILON: f64 = 1.0e-30;

/// Coverage of a shape: alpha 0..=255 per pixel over `[x0, x0 + w) x [y0,
/// y0 + h)`.
#[derive(Clone, Debug, Default)]
pub struct Coverage {
    pub x0: i32,
    pub y0: i32,
    pub w: usize,
    pub h: usize,
    pub alpha: Vec<u8>,
}

/// `agg::iround()`.
fn iround(v: f64) -> i32 {
    (if v < 0.0 { v - 0.5 } else { v + 0.5 }) as i32
}

/// Cells (cover, area) summed per pixel over a fixed box.
struct Cells {
    x0: i32,
    y0: i32,
    w: i32,
    h: i32,
    cover: Vec<i32>,
    area: Vec<i32>,
    cx: i32,
    cy: i32,
}

impl Cells {
    fn new(x0: i32, y0: i32, w: i32, h: i32) -> Self {
        let n = (w * h) as usize;
        Cells { x0, y0, w, h, cover: vec![0; n], area: vec![0; n], cx: 0, cy: 0 }
    }

    fn set_curr_cell(&mut self, x: i32, y: i32) {
        self.cx = x;
        self.cy = y;
    }

    fn add(&mut self, cover: i32, area: i32) {
        let (i, j) = (self.cx - self.x0, self.cy - self.y0);
        if j < 0 || j >= self.h || i >= self.w {
            return;
        }
        if i < 0 {
            // Left of the box, a cell only adds its cover to the pixels to
            // its right (its area belongs to its own pixel).
            self.cover[(j * self.w) as usize] += cover;
            return;
        }
        let k = (j * self.w + i) as usize;
        self.cover[k] += cover;
        self.area[k] += area;
    }

    fn render_hline(&mut self, ey: i32, x1: i32, y1: i32, x2: i32, y2: i32) {
        let mut ex1 = x1 >> SHIFT;
        let ex2 = x2 >> SHIFT;
        let fx1 = x1 & MASK;
        let fx2 = x2 & MASK;
        if y1 == y2 {
            self.set_curr_cell(ex2, ey);
            return;
        }
        if ex1 == ex2 {
            let delta = y2 - y1;
            self.add(delta, (fx1 + fx2) * delta);
            return;
        }
        let mut p = (SCALE - fx1) * (y2 - y1);
        let mut first = SCALE;
        let mut incr = 1;
        let mut dx = x2 as i64 - x1 as i64;
        if dx < 0 {
            p = fx1 * (y2 - y1);
            first = 0;
            incr = -1;
            dx = -dx;
        }
        let mut delta = (p as i64 / dx) as i32;
        let mut m = (p as i64 % dx) as i32;
        if m < 0 {
            delta -= 1;
            m += dx as i32;
        }
        self.add(delta, (fx1 + first) * delta);
        ex1 += incr;
        self.set_curr_cell(ex1, ey);
        let mut y1 = y1 + delta;
        if ex1 != ex2 {
            let p = SCALE as i64 * (y2 - y1 + delta) as i64;
            let mut lift = (p / dx) as i32;
            let mut rem = (p % dx) as i32;
            if rem < 0 {
                lift -= 1;
                rem += dx as i32;
            }
            m -= dx as i32;
            while ex1 != ex2 {
                delta = lift;
                m += rem;
                if m >= 0 {
                    m -= dx as i32;
                    delta += 1;
                }
                self.add(delta, SCALE * delta);
                y1 += delta;
                ex1 += incr;
                self.set_curr_cell(ex1, ey);
            }
        }
        let delta = y2 - y1;
        self.add(delta, (fx2 + SCALE - first) * delta);
    }

    fn line(&mut self, x1: i32, y1: i32, x2: i32, y2: i32) {
        let dx = x2 as i64 - x1 as i64;
        let mut dy = y2 as i64 - y1 as i64;
        let ex1 = x1 >> SHIFT;
        let mut ey1 = y1 >> SHIFT;
        let ey2 = y2 >> SHIFT;
        let fy1 = y1 & MASK;
        let fy2 = y2 & MASK;
        self.set_curr_cell(ex1, ey1);
        if ey1 == ey2 {
            self.render_hline(ey1, x1, fy1, x2, fy2);
            return;
        }
        let mut incr = 1;
        if dx == 0 {
            let ex = x1 >> SHIFT;
            let two_fx = (x1 - (ex << SHIFT)) << 1;
            let mut first = SCALE;
            if dy < 0 {
                first = 0;
                incr = -1;
            }
            let delta = first - fy1;
            self.add(delta, two_fx * delta);
            ey1 += incr;
            self.set_curr_cell(ex, ey1);
            let delta = first + first - SCALE;
            let area = two_fx * delta;
            while ey1 != ey2 {
                self.add(delta, area);
                ey1 += incr;
                self.set_curr_cell(ex, ey1);
            }
            let delta = fy2 - SCALE + first;
            self.add(delta, two_fx * delta);
            return;
        }
        let mut p = (SCALE - fy1) as i64 * dx;
        let mut first = SCALE;
        if dy < 0 {
            p = fy1 as i64 * dx;
            first = 0;
            incr = -1;
            dy = -dy;
        }
        let mut delta = (p / dy) as i32;
        let mut m = (p % dy) as i32;
        if m < 0 {
            delta -= 1;
            m += dy as i32;
        }
        let mut x_from = x1 + delta;
        self.render_hline(ey1, x1, fy1, x_from, first);
        ey1 += incr;
        self.set_curr_cell(x_from >> SHIFT, ey1);
        if ey1 != ey2 {
            let p = SCALE as i64 * dx;
            let mut lift = (p / dy) as i32;
            let mut rem = (p % dy) as i32;
            if rem < 0 {
                lift -= 1;
                rem += dy as i32;
            }
            m -= dy as i32;
            while ey1 != ey2 {
                delta = lift;
                m += rem;
                if m >= 0 {
                    m -= dy as i32;
                    delta += 1;
                }
                let x_to = x_from + delta;
                self.render_hline(ey1, x_from, SCALE - first, x_to, first);
                x_from = x_to;
                ey1 += incr;
                self.set_curr_cell(x_from >> SHIFT, ey1);
            }
        }
        self.render_hline(ey1, x_from, SCALE - first, x2, fy2);
    }
}

/// Filling rule (`agg::filling_rule_e`).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Rule {
    NonZero,
    EvenOdd,
}

/// `calculate_alpha()` with AGG's identity gamma.
fn calculate_alpha(area: i32, rule: Rule) -> u8 {
    let mut cover = (area >> (SHIFT * 2 + 1 - 8)).unsigned_abs();
    if rule == Rule::EvenOdd {
        cover &= 511;
        if cover > 256 {
            cover = 512 - cover;
        }
    }
    cover.min(255) as u8
}

/// Rasterises closed contours (each implicitly closed, as AGG's
/// `close_polygon()` does) with the non-zero rule.
pub fn rasterize(contours: &[Vec<[f64; 2]>]) -> Coverage {
    let (mut lo_x, mut lo_y, mut hi_x, mut hi_y) = (i32::MAX, i32::MAX, i32::MIN, i32::MIN);
    for &[x, y] in contours.iter().flatten() {
        let (ix, iy) = (iround(x * SCALE as f64), iround(y * SCALE as f64));
        lo_x = lo_x.min(ix >> SHIFT);
        hi_x = hi_x.max(ix >> SHIFT);
        lo_y = lo_y.min(iy >> SHIFT);
        hi_y = hi_y.max(iy >> SHIFT);
    }
    if lo_x > hi_x {
        return Coverage::default();
    }
    rasterize_in(contours, Rule::NonZero, lo_x, lo_y, hi_x + 1, hi_y + 1)
}

/// Rasterises closed contours with `rule` over pixels `[x0, x1) x [y0,
/// y1)` only. Edges outside those rows are skipped and cover from left of
/// the box is carried in, so each pixel's alpha is what a full
/// rasterisation gives: a band of a page can rasterise its rows alone.
pub fn rasterize_in(contours: &[Vec<[f64; 2]>], rule: Rule, x0: i32, y0: i32, x1: i32, y1: i32) -> Coverage {
    let (w, h) = (x1 - x0, y1 - y0);
    if w <= 0 || h <= 0 {
        return Coverage::default();
    }
    let mut cells = Cells::new(x0, y0, w, h);
    let (top, bottom) = (y0 << SHIFT, y1 << SHIFT);
    let up = |p: &[f64; 2]| (iround(p[0] * SCALE as f64), iround(p[1] * SCALE as f64));
    for c in contours {
        if c.len() < 2 {
            continue;
        }
        let start = up(&c[0]);
        let mut prev = start;
        for q in c[1..].iter().map(up).chain(std::iter::once(start)) {
            // An edge wholly above or below the rows adds to no cell in them.
            if !((prev.1 < top && q.1 < top) || (prev.1 >= bottom && q.1 >= bottom)) {
                cells.line(prev.0, prev.1, q.0, q.1);
            }
            prev = q;
        }
    }
    let mut alpha = vec![0u8; (w * h) as usize];
    for j in 0..h as usize {
        let mut cover = 0i32;
        for i in 0..w as usize {
            let k = j * w as usize + i;
            cover += cells.cover[k];
            let v = ((cover as u32) << (SHIFT + 1)) as i32;
            alpha[k] = calculate_alpha(v.wrapping_sub(cells.area[k]), rule);
        }
    }
    Coverage { x0, y0, w: w as usize, h: h as usize, alpha }
}

/// The pieces `conv_dash` cuts a path into (`vcgen_dash`,
/// agg_vcgen_dash.cpp), as open polylines, for alternating dash and gap
/// lengths `dashes` starting with a dash.
pub fn dash(path: &[[f64; 2]], closed: bool, dashes: &[f64]) -> Vec<Vec<[f64; 2]>> {
    let mut v: Vec<Vd> = Vec::with_capacity(path.len());
    push_vertices(&mut v, path, closed);
    let n = v.len();
    if dashes.len() < 2 || n < 2 {
        return Vec::new();
    }
    let mut out: Vec<Vec<[f64; 2]>> = Vec::new();
    let mut piece: Vec<[f64; 2]> = vec![[v[0].x, v[0].y]];
    let (mut curr_dash, mut curr_dash_start) = (0usize, 0.0f64);
    let mut src = 1usize;
    let (mut v1, mut v2) = (0usize, 1usize);
    let mut curr_rest = v[v1].dist;
    // conv_adaptor_vcgen hands each move_to-started run to the stroker.
    let mut emit = |cmd_move: bool, p: [f64; 2], piece: &mut Vec<[f64; 2]>| {
        if cmd_move {
            if piece.len() >= 2 {
                out.push(std::mem::take(piece));
            }
            piece.clear();
        }
        piece.push(p);
    };
    loop {
        let dash_rest = dashes[curr_dash] - curr_dash_start;
        let cmd_move = curr_dash & 1 == 1;
        if curr_rest > dash_rest {
            curr_rest -= dash_rest;
            curr_dash += 1;
            if curr_dash >= dashes.len() {
                curr_dash = 0;
            }
            curr_dash_start = 0.0;
            let (a, b) = (&v[v1], &v[v2]);
            let p = [b.x - (b.x - a.x) * curr_rest / a.dist, b.y - (b.y - a.y) * curr_rest / a.dist];
            emit(cmd_move, p, &mut piece);
        } else {
            curr_dash_start += curr_rest;
            let p = [v[v2].x, v[v2].y];
            emit(cmd_move, p, &mut piece);
            src += 1;
            v1 = v2;
            curr_rest = v[v1].dist;
            if closed {
                if src > n {
                    break;
                }
                v2 = if src >= n { 0 } else { src };
            } else {
                if src >= n {
                    break;
                }
                v2 = src;
            }
        }
    }
    if piece.len() >= 2 {
        out.push(piece);
    }
    out
}

/// Clips closed contours to an axis-aligned box (Sutherland-Hodgman, each
/// contour separately), as AGG's rasteriser clips to its clip box before
/// computing coverage. For a convex box this keeps the non-zero winding of
/// every point inside it, so the coverage is the clipped shape's.
pub fn clip_contours(contours: &[Vec<[f64; 2]>], x0: f64, y0: f64, x1: f64, y1: f64) -> Vec<Vec<[f64; 2]>> {
    fn clip_edge(poly: &[[f64; 2]], inside: impl Fn(&[f64; 2]) -> bool, cut: impl Fn(&[f64; 2], &[f64; 2]) -> [f64; 2]) -> Vec<[f64; 2]> {
        let mut out = Vec::with_capacity(poly.len() + 4);
        for i in 0..poly.len() {
            let (a, b) = (&poly[i], &poly[(i + 1) % poly.len()]);
            match (inside(a), inside(b)) {
                (true, true) => out.push(*b),
                (true, false) => out.push(cut(a, b)),
                (false, true) => {
                    out.push(cut(a, b));
                    out.push(*b);
                }
                (false, false) => {}
            }
        }
        out
    }
    let at_x = |x: f64| move |a: &[f64; 2], b: &[f64; 2]| [x, a[1] + (b[1] - a[1]) * (x - a[0]) / (b[0] - a[0])];
    let at_y = |y: f64| move |a: &[f64; 2], b: &[f64; 2]| [a[0] + (b[0] - a[0]) * (y - a[1]) / (b[1] - a[1]), y];
    contours
        .iter()
        .map(|c| {
            let c = clip_edge(c, |p| p[0] >= x0, at_x(x0));
            let c = clip_edge(&c, |p| p[0] <= x1, at_x(x1));
            let c = clip_edge(&c, |p| p[1] >= y0, at_y(y0));
            clip_edge(&c, |p| p[1] <= y1, at_y(y1))
        })
        .filter(|c| c.len() >= 3)
        .collect()
}

/// `agg::ellipse` vertices for a circle with `n` steps, from angle 0
/// counter-clockwise in device space (y down).
pub fn ellipse(x: f64, y: f64, r: f64, n: usize) -> Vec<[f64; 2]> {
    (0..n)
        .map(|k| {
            let a = k as f64 / n as f64 * 2.0 * std::f64::consts::PI;
            [x + a.cos() * r, y + a.sin() * r]
        })
        .collect()
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Cap {
    Butt,
    Square,
    Round,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Join {
    Miter,
    Round,
    Bevel,
}

#[derive(Clone, Copy)]
struct Vd {
    x: f64,
    y: f64,
    dist: f64,
}

fn dist(a: &Vd, b: &Vd) -> f64 {
    (b.x - a.x).hypot(b.y - a.y)
}

fn cross_product(x1: f64, y1: f64, x2: f64, y2: f64, x: f64, y: f64) -> f64 {
    (x - x2) * (y2 - y1) - (y - y2) * (x2 - x1)
}

#[allow(clippy::too_many_arguments)]
fn calc_intersection(ax: f64, ay: f64, bx: f64, by: f64, cx: f64, cy: f64, dx: f64, dy: f64) -> Option<(f64, f64)> {
    let num = (ay - cy) * (dx - cx) - (ax - cx) * (dy - cy);
    let den = (bx - ax) * (dy - cy) - (by - ay) * (dx - cx);
    if den.abs() < INTERSECTION_EPSILON {
        return None;
    }
    let r = num / den;
    Some((ax + r * (bx - ax), ay + r * (by - ay)))
}

/// `math_stroke` with AGG's defaults for what ragg does not set.
struct MathStroke {
    width: f64,
    width_abs: f64,
    width_eps: f64,
    width_sign: f64,
    miter_limit: f64,
    inner_miter_limit: f64,
    approx_scale: f64,
    cap: Cap,
    join: Join,
}

impl MathStroke {
    fn new(width: f64, join: Join, cap: Cap, miter_limit: f64) -> Self {
        let w = width * 0.5;
        MathStroke {
            width: w,
            width_abs: w.abs(),
            width_eps: w / 1024.0,
            width_sign: if w < 0.0 { -1.0 } else { 1.0 },
            miter_limit,
            inner_miter_limit: 1.01,
            approx_scale: 1.0,
            cap,
            join,
        }
    }

    fn calc_arc(&self, vc: &mut Vec<[f64; 2]>, x: f64, y: f64, dx1: f64, dy1: f64, dx2: f64, dy2: f64) {
        let mut a1 = (dy1 * self.width_sign).atan2(dx1 * self.width_sign);
        let mut a2 = (dy2 * self.width_sign).atan2(dx2 * self.width_sign);
        let mut da = (self.width_abs / (self.width_abs + 0.125 / self.approx_scale)).acos() * 2.0;
        let pi = std::f64::consts::PI;
        vc.push([x + dx1, y + dy1]);
        if self.width_sign > 0.0 {
            if a1 > a2 {
                a2 += 2.0 * pi;
            }
            let n = ((a2 - a1) / da) as i32;
            da = (a2 - a1) / (n + 1) as f64;
            a1 += da;
            for _ in 0..n {
                vc.push([x + a1.cos() * self.width, y + a1.sin() * self.width]);
                a1 += da;
            }
        } else {
            if a1 < a2 {
                a2 -= 2.0 * pi;
            }
            let n = ((a1 - a2) / da) as i32;
            da = (a1 - a2) / (n + 1) as f64;
            a1 -= da;
            for _ in 0..n {
                vc.push([x + a1.cos() * self.width, y + a1.sin() * self.width]);
                a1 -= da;
            }
        }
        vc.push([x + dx2, y + dy2]);
    }

    /// `calc_miter()` for the joins ragg can reach: `miter_join` (from
    /// `linejoin = "mitre"`) and `miter_join_revert` (inner joins).
    #[allow(clippy::too_many_arguments)]
    fn calc_miter(&self, vc: &mut Vec<[f64; 2]>, v0: &Vd, v1: &Vd, v2: &Vd, dx1: f64, dy1: f64, dx2: f64, dy2: f64, revert: bool, mut mlimit: f64, dbevel: f64) {
        let (mut xi, mut yi) = (v1.x, v1.y);
        let mut di = 1.0;
        let lim = self.width_abs * mlimit;
        let mut miter_limit_exceeded = true;
        let mut intersection_failed = true;
        if let Some((x, y)) = calc_intersection(v0.x + dx1, v0.y - dy1, v1.x + dx1, v1.y - dy1, v1.x + dx2, v1.y - dy2, v2.x + dx2, v2.y - dy2) {
            xi = x;
            yi = y;
            di = (xi - v1.x).hypot(yi - v1.y);
            if di <= lim {
                vc.push([xi, yi]);
                miter_limit_exceeded = false;
            }
            intersection_failed = false;
        } else {
            let x2 = v1.x + dx1;
            let y2 = v1.y - dy1;
            if (cross_product(v0.x, v0.y, v1.x, v1.y, x2, y2) < 0.0) == (cross_product(v1.x, v1.y, v2.x, v2.y, x2, y2) < 0.0) {
                vc.push([v1.x + dx1, v1.y - dy1]);
                miter_limit_exceeded = false;
            }
        }
        if miter_limit_exceeded {
            if revert {
                vc.push([v1.x + dx1, v1.y - dy1]);
                vc.push([v1.x + dx2, v1.y - dy2]);
            } else if intersection_failed {
                mlimit *= self.width_sign;
                vc.push([v1.x + dx1 + dy1 * mlimit, v1.y - dy1 + dx1 * mlimit]);
                vc.push([v1.x + dx2 - dy2 * mlimit, v1.y - dy2 - dx2 * mlimit]);
            } else {
                let (x1, y1) = (v1.x + dx1, v1.y - dy1);
                let (x2, y2) = (v1.x + dx2, v1.y - dy2);
                di = (lim - dbevel) / (di - dbevel);
                vc.push([x1 + (xi - x1) * di, y1 + (yi - y1) * di]);
                vc.push([x2 + (xi - x2) * di, y2 + (yi - y2) * di]);
            }
        }
    }

    fn calc_cap(&self, vc: &mut Vec<[f64; 2]>, v0: &Vd, v1: &Vd, len: f64) {
        let mut dx1 = (v1.y - v0.y) / len;
        let mut dy1 = (v1.x - v0.x) / len;
        let (mut dx2, mut dy2) = (0.0, 0.0);
        dx1 *= self.width;
        dy1 *= self.width;
        if self.cap != Cap::Round {
            if self.cap == Cap::Square {
                dx2 = dy1 * self.width_sign;
                dy2 = dx1 * self.width_sign;
            }
            vc.push([v0.x - dx1 - dx2, v0.y + dy1 - dy2]);
            vc.push([v0.x + dx1 - dx2, v0.y - dy1 - dy2]);
        } else {
            let pi = std::f64::consts::PI;
            let mut da = (self.width_abs / (self.width_abs + 0.125 / self.approx_scale)).acos() * 2.0;
            let n = (pi / da) as i32;
            da = pi / (n + 1) as f64;
            vc.push([v0.x - dx1, v0.y + dy1]);
            if self.width_sign > 0.0 {
                let mut a1 = dy1.atan2(-dx1);
                a1 += da;
                for _ in 0..n {
                    vc.push([v0.x + a1.cos() * self.width, v0.y + a1.sin() * self.width]);
                    a1 += da;
                }
            } else {
                let mut a1 = (-dy1).atan2(dx1);
                a1 -= da;
                for _ in 0..n {
                    vc.push([v0.x + a1.cos() * self.width, v0.y + a1.sin() * self.width]);
                    a1 -= da;
                }
            }
            vc.push([v0.x + dx1, v0.y - dy1]);
        }
    }

    fn calc_join(&self, vc: &mut Vec<[f64; 2]>, v0: &Vd, v1: &Vd, v2: &Vd, len1: f64, len2: f64) {
        let dx1 = self.width * (v1.y - v0.y) / len1;
        let dy1 = self.width * (v1.x - v0.x) / len1;
        let dx2 = self.width * (v2.y - v1.y) / len2;
        let dy2 = self.width * (v2.x - v1.x) / len2;
        let cp = cross_product(v0.x, v0.y, v1.x, v1.y, v2.x, v2.y);
        if cp != 0.0 && (cp > 0.0) == (self.width > 0.0) {
            // Inner join: AGG's default `inner_miter`.
            let mut limit = len1.min(len2) / self.width_abs;
            if limit < self.inner_miter_limit {
                limit = self.inner_miter_limit;
            }
            self.calc_miter(vc, v0, v1, v2, dx1, dy1, dx2, dy2, true, limit, 0.0);
        } else {
            let (mut dx, mut dy) = ((dx1 + dx2) / 2.0, (dy1 + dy2) / 2.0);
            let dbevel = (dx * dx + dy * dy).sqrt();
            if (self.join == Join::Round || self.join == Join::Bevel) && self.approx_scale * (self.width_abs - dbevel) < self.width_eps {
                if let Some((x, y)) = calc_intersection(v0.x + dx1, v0.y - dy1, v1.x + dx1, v1.y - dy1, v1.x + dx2, v1.y - dy2, v2.x + dx2, v2.y - dy2) {
                    dx = x;
                    dy = y;
                    vc.push([dx, dy]);
                } else {
                    vc.push([v1.x + dx1, v1.y - dy1]);
                }
                return;
            }
            match self.join {
                Join::Miter => self.calc_miter(vc, v0, v1, v2, dx1, dy1, dx2, dy2, false, self.miter_limit, dbevel),
                Join::Round => self.calc_arc(vc, v1.x, v1.y, dx1, -dy1, dx2, -dy2),
                Join::Bevel => {
                    vc.push([v1.x + dx1, v1.y - dy1]);
                    vc.push([v1.x + dx2, v1.y - dy2]);
                }
            }
        }
    }
}

/// `vertex_sequence::add()` and `close()`: drops coincident vertices and
/// sets each vertex's distance to the next (the last to the first if
/// `closed`).
fn push_vertices(v: &mut Vec<Vd>, path: &[[f64; 2]], closed: bool) {
    for &[x, y] in path {
        let p = Vd { x, y, dist: 0.0 };
        if v.len() > 1 && dist(&v[v.len() - 2], &v[v.len() - 1]) <= VERTEX_DIST_EPSILON {
            v.pop();
        }
        v.push(p);
    }
    while v.len() > 1 && dist(&v[v.len() - 2], &v[v.len() - 1]) <= VERTEX_DIST_EPSILON {
        let t = v.pop().unwrap();
        v.pop();
        v.push(t);
    }
    if closed {
        while v.len() > 1 && dist(&v[v.len() - 1], &v[0]) <= VERTEX_DIST_EPSILON {
            v.pop();
        }
    }
    let n = v.len();
    for i in 0..n {
        if i + 1 < n {
            v[i].dist = dist(&v[i], &v[i + 1]);
        } else if closed {
            v[i].dist = dist(&v[i], &v[0]);
        }
    }
}

/// The outline contours `conv_stroke` produces for a path (`vcgen_stroke`):
/// two contours for a closed path, one for an open one.
pub fn stroke(path: &[[f64; 2]], closed: bool, width: f64, join: Join, cap: Cap, miter_limit: f64) -> Vec<Vec<[f64; 2]>> {
    let mut v: Vec<Vd> = Vec::with_capacity(path.len());
    push_vertices(&mut v, path, closed);
    let n = v.len();
    let closed = closed && n >= 3;
    if n < 2 + closed as usize {
        return Vec::new();
    }
    let s = MathStroke::new(width, join, cap, miter_limit);
    let prev = |i: usize| (i + n - 1) % n;
    let next = |i: usize| (i + 1) % n;
    let mut vc = Vec::new();
    let mut out = Vec::new();
    if closed {
        let mut c1 = Vec::new();
        for i in 0..n {
            vc.clear();
            s.calc_join(&mut vc, &v[prev(i)], &v[i], &v[next(i)], v[prev(i)].dist, v[i].dist);
            c1.extend_from_slice(&vc);
        }
        let mut c2 = Vec::new();
        for i in (0..n).rev() {
            vc.clear();
            s.calc_join(&mut vc, &v[next(i)], &v[i], &v[prev(i)], v[i].dist, v[prev(i)].dist);
            c2.extend_from_slice(&vc);
        }
        out.push(c1);
        out.push(c2);
    } else {
        let mut c = Vec::new();
        s.calc_cap(&mut c, &v[0], &v[1], v[0].dist);
        for i in 1..n - 1 {
            vc.clear();
            s.calc_join(&mut vc, &v[i - 1], &v[i], &v[i + 1], v[i - 1].dist, v[i].dist);
            c.extend_from_slice(&vc);
        }
        vc.clear();
        s.calc_cap(&mut vc, &v[n - 1], &v[n - 2], v[n - 2].dist);
        c.extend_from_slice(&vc);
        for i in (1..n - 1).rev() {
            vc.clear();
            s.calc_join(&mut vc, &v[i + 1], &v[i], &v[i - 1], v[i].dist, v[i - 1].dist);
            c.extend_from_slice(&vc);
        }
        out.push(c);
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn at(c: &Coverage, x: i32, y: i32) -> u8 {
        let (i, j) = (x - c.x0, y - c.y0);
        if i < 0 || j < 0 || i >= c.w as i32 || j >= c.h as i32 {
            return 0;
        }
        c.alpha[j as usize * c.w + i as usize]
    }

    #[test]
    fn pixel_aligned_square_is_fully_covered() {
        let c = rasterize(&[vec![[1.0, 1.0], [4.0, 1.0], [4.0, 3.0], [1.0, 3.0]]]);
        for y in 0..5 {
            for x in 0..6 {
                let inside = (1..4).contains(&x) && (1..3).contains(&y);
                assert_eq!(at(&c, x, y), if inside { 255 } else { 0 }, "{x},{y}");
            }
        }
    }

    #[test]
    fn coverage_is_the_exact_area() {
        // Half a pixel wide, so 128 (AGG: (256 * 256 / 2) >> 9 = 64 * 2).
        let c = rasterize(&[vec![[2.5, 0.0], [3.0, 0.0], [3.0, 1.0], [2.5, 1.0]]]);
        assert_eq!(at(&c, 2, 0), 128);
        // A diagonal halves a pixel too; orientation doesn't matter.
        let c = rasterize(&[vec![[0.0, 0.0], [1.0, 1.0], [0.0, 1.0]]]);
        assert_eq!(at(&c, 0, 0), 128);
        let c = rasterize(&[vec![[0.0, 1.0], [1.0, 1.0], [0.0, 0.0]]]);
        assert_eq!(at(&c, 0, 0), 128);
    }

    #[test]
    fn nonzero_rule_unions_overlaps() {
        let a = vec![[0.0, 0.0], [2.0, 0.0], [2.0, 2.0], [0.0, 2.0]];
        let b = vec![[1.0, 1.0], [3.0, 1.0], [3.0, 3.0], [1.0, 3.0]];
        let c = rasterize(&[a, b]);
        assert_eq!(at(&c, 1, 1), 255);
        assert_eq!(at(&c, 2, 2), 255);
        assert_eq!(at(&c, 2, 0), 0);
    }

    #[test]
    fn clipping_keeps_the_area_inside_the_box() {
        let sq = vec![vec![[0.0, 0.0], [4.0, 0.0], [4.0, 4.0], [0.0, 4.0]]];
        let c = rasterize(&clip_contours(&sq, 1.5, -1.0, 10.0, 2.25));
        assert_eq!(at(&c, 1, 1), 128);
        assert_eq!(at(&c, 2, 1), 255);
        assert_eq!(at(&c, 2, 2), 64);
        assert_eq!(at(&c, 2, 3), 0);
        // A stroked ring keeps its hole.
        let ring = stroke(&[[0.0, 0.0], [10.0, 0.0], [10.0, 10.0], [0.0, 10.0]], true, 2.0, Join::Round, Cap::Round, 10.0);
        let c = rasterize(&clip_contours(&ring, -5.0, 3.0, 15.0, 15.0));
        assert_eq!(at(&c, 5, 5), 0);
        assert_eq!(at(&c, 0, 5), 255);
        assert_eq!(at(&c, 0, 2), 0);
    }

    #[test]
    fn rasterising_a_box_matches_the_full_rasterisation() {
        let ring = stroke(&[[1.3, 2.2], [17.8, 4.1], [9.4, 15.6]], true, 2.5, Join::Round, Cap::Round, 10.0);
        let full = rasterize(&ring);
        for (x0, y0, x1, y1) in [(5, 3, 12, 9), (0, 10, 20, 11), (-3, -3, 25, 25)] {
            let part = rasterize_in(&ring, Rule::NonZero, x0, y0, x1, y1);
            for y in y0..y1 {
                for x in x0..x1 {
                    let got = part.alpha[((y - y0) * (x1 - x0) + (x - x0)) as usize];
                    assert_eq!(got, at(&full, x, y), "{x},{y}");
                }
            }
        }
    }

    #[test]
    fn even_odd_leaves_overlaps_empty() {
        let a = vec![[0.0, 0.0], [2.0, 0.0], [2.0, 2.0], [0.0, 2.0]];
        let b = vec![[1.0, 1.0], [3.0, 1.0], [3.0, 3.0], [1.0, 3.0]];
        let c = rasterize_in(&[a, b], Rule::EvenOdd, 0, 0, 4, 4);
        assert_eq!(c.alpha[4 + 1], 0);
        assert_eq!(c.alpha[0], 255);
        assert_eq!(c.alpha[2 * 4 + 2], 255);
    }

    #[test]
    fn dashes_cut_the_path() {
        // 10 px dash, 5 px gap along a 40 px line, then around a corner.
        let p = dash(&[[0.0, 0.0], [40.0, 0.0]], false, &[10.0, 5.0]);
        let xs: Vec<[f64; 2]> = p.iter().map(|d| [d[0][0], d[d.len() - 1][0]]).collect();
        assert_eq!(xs, vec![[0.0, 10.0], [15.0, 25.0], [30.0, 40.0]]);
        let p = dash(&[[0.0, 0.0], [8.0, 0.0], [8.0, 8.0]], false, &[12.0, 2.0]);
        assert_eq!(p[0], vec![[0.0, 0.0], [8.0, 0.0], [8.0, 4.0]]);
        assert_eq!(p[1], vec![[8.0, 6.0], [8.0, 8.0]]);
    }

    #[test]
    fn stroke_of_a_line_has_round_caps() {
        let c = stroke(&[[10.0, 10.0], [20.0, 10.0]], false, 4.0, Join::Round, Cap::Round, 10.0);
        assert_eq!(c.len(), 1);
        let xs = c[0].iter().map(|p| p[0]);
        let (lo, hi) = xs.fold((f64::MAX, f64::MIN), |(a, b), x| (a.min(x), b.max(x)));
        // The cap arcs reach to within the approximation of x = 8 and 22.
        assert!(lo > 8.0 - 1e-9 && lo < 8.1 && hi < 22.0 + 1e-9 && hi > 21.9, "{lo} {hi}");
        let cov = rasterize(&c);
        assert_eq!(at(&cov, 15, 9), 255);
        assert_eq!(at(&cov, 15, 12), 0);
    }

    #[test]
    fn stroke_of_a_closed_square_has_two_contours_and_a_hole() {
        let sq = [[0.0, 0.0], [10.0, 0.0], [10.0, 10.0], [0.0, 10.0]];
        let c = stroke(&sq, true, 2.0, Join::Round, Cap::Round, 10.0);
        assert_eq!(c.len(), 2);
        let cov = rasterize(&c);
        assert_eq!(at(&cov, 5, 5), 0);
        assert_eq!(at(&cov, 5, 0), 255);
        assert_eq!(at(&cov, 5, -1), 255);
        assert_eq!(at(&cov, 5, -2), 0);
        assert_eq!(at(&cov, 5, 1), 0);
        assert_eq!(at(&cov, 0, 5), 255);
    }
}
