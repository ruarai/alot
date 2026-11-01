//! The page display list (PHASE2.md, Architecture 5): drawing primitives in
//! device pixels (origin top-left, pixel `i` covers `[i, i + 1)`), in
//! drawing order. `raster` executes it band by band.

use crate::render::paths::PathBatch;
use crate::render::points::PointBatch;
use crate::render::raster::RasterDraw;
use crate::render::rects::RectBatch;
use crate::render::text::Image;

/// An axis-aligned box in device pixels; edges may be fractional.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Rect {
    pub x0: f64,
    pub y0: f64,
    pub x1: f64,
    pub y1: f64,
}

impl Rect {
    pub fn intersect(&self, o: &Rect) -> Rect {
        Rect { x0: self.x0.max(o.x0), y0: self.y0.max(o.y0), x1: self.x1.min(o.x1), y1: self.y1.min(o.y1) }
    }

    /// Share of pixel row (or column) `i` inside `[lo, hi)`.
    fn overlap(i: usize, lo: f64, hi: f64) -> f32 {
        let (a, b) = (i as f64, i as f64 + 1.0);
        (hi.min(b) - lo.max(a)).clamp(0.0, 1.0) as f32
    }

    pub fn x_share(&self, i: usize) -> f32 {
        Self::overlap(i, self.x0, self.x1)
    }

    pub fn y_share(&self, j: usize) -> f32 {
        Self::overlap(j, self.y0, self.y1)
    }
}

/// One display-list item.
pub enum Item {
    /// Sets every pixel of the page to a colour (non-premultiplied RGBA),
    /// ignoring the clip, as ragg's `newPage()` does with
    /// `renderer.clear()` (ragg 1.5.2 src/AggDevice.h).
    Clear([u8; 4]),
    /// Clips later items to the intersection of this box and the current
    /// clip until the matching `PopClip`.
    PushClip(Rect),
    PopClip,
    Points(PointBatch),
    Rects(RectBatch),
    Paths(PathBatch),
    /// Premultiplied pixels blended over the page as they are, not clipped
    /// by the display clip (text is clipped when drawn, as ragg clips it).
    Image(Image),
    /// `geom_raster()`'s image, drawn as ragg's `drawRaster()` draws it and
    /// clipped by the display clip.
    Raster(RasterDraw),
}

impl Item {
    /// Pixel rows `[top, bottom)` the item can touch, or `None` if it
    /// applies to every band (clears and clip changes).
    pub fn rows(&self) -> Option<(i64, i64)> {
        match self {
            Item::Clear(_) | Item::PushClip(_) | Item::PopClip => None,
            Item::Points(b) => Some(b.rows()),
            Item::Rects(b) => Some(b.rows()),
            Item::Paths(b) => Some(b.rows()),
            Item::Image(i) => Some((i.y0 as i64, i.y0 as i64 + i.h as i64)),
            Item::Raster(r) => Some(r.rows()),
        }
    }
}

/// The items of one page, in drawing order.
#[derive(Default)]
pub struct DisplayList {
    pub items: Vec<Item>,
}

impl DisplayList {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn push(&mut self, item: Item) {
        self.items.push(item);
    }
}
