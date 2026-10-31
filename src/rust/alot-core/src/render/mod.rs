//! Phase 2 rendering (see PHASE2.md): a display list of primitives in
//! device pixels, executed in row bands, and PNG encoding. The drawers are
//! the point, rect and path batches and text images; `page`, `panel`, `axis`
//! and `title` draw a plot's page from them in the full tier.

pub mod agg;
pub mod axis;
pub mod display;
pub mod layers;
pub mod layout;
pub mod legend;
pub mod page;
pub mod panel;
pub mod paths;
pub mod png;
pub mod points;
pub mod raster;
pub mod rects;
pub mod text;
pub mod title;
