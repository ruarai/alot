//! Phase 2 rendering (see PHASE2.md): a display list of primitives in
//! device pixels, executed in row bands, and PNG encoding. So far the
//! drawers are the point, rect and path batches the hybrid tier uses.

pub mod agg;
pub mod display;
pub mod paths;
pub mod png;
pub mod points;
pub mod raster;
pub mod rects;
