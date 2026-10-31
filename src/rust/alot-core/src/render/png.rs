//! PNG encoding for rendered pages, streamed row by row and compressed in
//! parallel. ragg's PNG writer (libpng at its default zlib level) costs
//! more than drawing a busy plot.
//!
//! Rows are Sub-filtered (the png crate's default) and grouped into chunks
//! of about `CHUNK` bytes. Each chunk is deflated at level 1 on its own
//! thread, ending with a sync flush (the last with the final block), as
//! pigz does, and written as its own IDAT chunk; the zlib header and the
//! Adler-32 (combined from the chunks') go in IDAT chunks of their own.
//! Chunks are compressed `threads` at a time as rows arrive, so memory is
//! bounded however tall the page. This was 5-9x faster than fdeflate's
//! fast mode on README-like pages, for files 5-10% larger
//! (inst/bench/RESULTS.md, R1.5).
//!
//! Files carry what ragg's `agg_png()` writes (ragg 1.5.2 src/png_dev.cpp,
//! src/AggDevicePng.h): 8-bit RGB when the background is opaque, RGBA
//! otherwise; a `bKGD` chunk with the background premultiplied by its
//! alpha; and a `pHYs` chunk from the resolution, in that order.

use crate::render::display::{DisplayList, Item};
use crate::render::raster::{self, Options};
use flate2::{Compress, Compression, FlushCompress, Status};
use std::io::Write;

/// Target size of a compressed chunk's input, in bytes.
const CHUNK: usize = 512 << 10;

/// What goes in the header: colour type, background and resolution.
#[derive(Clone, Copy, Debug)]
pub struct PngOptions {
    /// RGBA (else RGB, dropping alpha).
    pub alpha: bool,
    /// The device background, non-premultiplied RGBA.
    pub background: [u8; 4],
    /// Pixels per inch for `pHYs`, if any.
    pub dpi: Option<f64>,
}

impl PngOptions {
    /// As ragg chooses for background `bg`: RGBA unless `bg` is opaque.
    pub fn for_background(bg: [u8; 4], dpi: Option<f64>) -> Self {
        PngOptions { alpha: bg[3] != 255, background: bg, dpi }
    }
}

/// AGG's 8-bit multiply (`rgba8::multiply`), as `premultiply()` uses it.
fn agg_multiply(a: u8, b: u8) -> u8 {
    let t = a as u32 * b as u32 + 128;
    (((t >> 8) + t) >> 8) as u8
}

/// A PNG chunk: length, type, data and CRC.
fn chunk(ty: &[u8; 4], data: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(data.len() + 12);
    out.extend_from_slice(&(data.len() as u32).to_be_bytes());
    out.extend_from_slice(ty);
    out.extend_from_slice(data);
    let mut crc = crc32fast::Hasher::new();
    crc.update(ty);
    crc.update(data);
    out.extend_from_slice(&crc.finalize().to_be_bytes());
    out
}

const ADLER_MOD: u32 = 65521;

fn adler32(data: &[u8]) -> u32 {
    let (mut a, mut b) = (1u32, 0u32);
    // 5552 bytes keep the sums below 2^32 before reducing (zlib's NMAX).
    for block in data.chunks(5552) {
        for &x in block {
            a += x as u32;
            b += a;
        }
        a %= ADLER_MOD;
        b %= ADLER_MOD;
    }
    (b << 16) | a
}

/// zlib's `adler32_combine()`: the Adler-32 of two concatenated inputs.
fn adler32_combine(a1: u32, a2: u32, len2: usize) -> u32 {
    let rem = (len2 % ADLER_MOD as usize) as u32;
    let mut sum1 = a1 & 0xffff;
    let mut sum2 = (rem * sum1) % ADLER_MOD;
    sum1 += (a2 & 0xffff) + ADLER_MOD - 1;
    sum2 += (a1 >> 16) + (a2 >> 16) + ADLER_MOD - rem;
    if sum1 >= ADLER_MOD {
        sum1 -= ADLER_MOD;
    }
    if sum1 >= ADLER_MOD {
        sum1 -= ADLER_MOD;
    }
    if sum2 >= ADLER_MOD << 1 {
        sum2 -= ADLER_MOD << 1;
    }
    if sum2 >= ADLER_MOD {
        sum2 -= ADLER_MOD;
    }
    (sum2 << 16) | sum1
}

/// Packs nativeRaster rows of `width` pixels as RGBA or RGB bytes, filters
/// them (Sub) and deflates them: the IDAT chunk, the filtered length and
/// its Adler-32.
fn compress_chunk(pixels: &[u32], width: usize, alpha: bool, last: bool) -> (Vec<u8>, usize, u32) {
    let bpp = if alpha { 4 } else { 3 };
    let row_bytes = width * bpp;
    let rows = pixels.len() / width.max(1);
    let mut filtered = Vec::with_capacity(rows * (row_bytes + 1));
    let mut line = vec![0u8; row_bytes];
    for row in pixels.chunks(width.max(1)) {
        if alpha {
            for (d, &p) in line.chunks_exact_mut(4).zip(row) {
                d.copy_from_slice(&p.to_le_bytes());
            }
        } else {
            for (d, &p) in line.chunks_exact_mut(3).zip(row) {
                d.copy_from_slice(&p.to_le_bytes()[..3]);
            }
        }
        filtered.push(1);
        filtered.extend_from_slice(&line[..bpp]);
        filtered.extend((bpp..row_bytes).map(|i| line[i].wrapping_sub(line[i - bpp])));
    }
    let mut z = Compress::new(Compression::fast(), false);
    let mut out = Vec::with_capacity(filtered.len() / 2 + 1024);
    let flush = if last { FlushCompress::Finish } else { FlushCompress::Sync };
    loop {
        let input = &filtered[z.total_in() as usize..];
        let status = z.compress_vec(input, &mut out, flush).expect("deflate");
        let done = z.total_in() as usize == filtered.len() && (if last { status == Status::StreamEnd } else { out.len() < out.capacity() });
        if done {
            break;
        }
        out.reserve(out.capacity().max(1024));
    }
    (chunk(b"IDAT", &out), filtered.len(), adler32(&filtered))
}

/// A PNG being written row by row, top to bottom.
pub struct Encoder<W: Write + 'static> {
    out: W,
    width: usize,
    alpha: bool,
    threads: usize,
    rows_left: usize,
    rows_per_chunk: usize,
    /// Rows not yet compressed, one buffer of pixels per pending chunk:
    /// packed to bytes by the compressing workers.
    pending: Vec<Vec<u32>>,
    adler: u32,
}

impl<W: Write + 'static> Encoder<W> {
    pub fn new(mut out: W, width: u32, height: u32, opts: &PngOptions) -> std::io::Result<Self> {
        let bpp = if opts.alpha { 4 } else { 3 };
        out.write_all(&[0x89, b'P', b'N', b'G', 0x0d, 0x0a, 0x1a, 0x0a])?;
        let mut ihdr = Vec::with_capacity(13);
        ihdr.extend_from_slice(&width.to_be_bytes());
        ihdr.extend_from_slice(&height.to_be_bytes());
        ihdr.extend_from_slice(&[8, if opts.alpha { 6 } else { 2 }, 0, 0, 0]);
        out.write_all(&chunk(b"IHDR", &ihdr))?;
        // ragg's order: bKGD (premultiplied, 16 bits per channel), then pHYs.
        let [r, g, b, a] = opts.background;
        let bkgd: Vec<u8> = [r, g, b].iter().flat_map(|&c| [0, agg_multiply(c, a)]).collect();
        out.write_all(&chunk(b"bKGD", &bkgd))?;
        if let Some(dpi) = opts.dpi {
            let ppm = ((dpi / 0.0254) as u32).to_be_bytes();
            let phys: Vec<u8> = ppm.iter().chain(ppm.iter()).copied().chain([1]).collect();
            out.write_all(&chunk(b"pHYs", &phys))?;
        }
        // zlib header: deflate, 32K window, fastest level.
        out.write_all(&chunk(b"IDAT", &[0x78, 0x01]))?;
        let row_bytes = width as usize * bpp;
        Ok(Encoder {
            out,
            width: width as usize,
            alpha: opts.alpha,
            threads: raster::default_threads(),
            rows_left: height as usize,
            rows_per_chunk: (CHUNK / row_bytes.max(1)).max(1),
            pending: Vec::new(),
            adler: 1,
        })
    }

    /// Writes whole rows of nativeRaster pixels (`R | G << 8 | B << 16 | A
    /// << 24`, non-premultiplied).
    pub fn write_rows(&mut self, pixels: &[u32]) -> std::io::Result<()> {
        let width = self.width;
        for row in pixels.chunks(width.max(1)) {
            let full = self.pending.last().map_or(true, |c| c.len() >= self.rows_per_chunk * width);
            if full {
                if self.pending.len() == self.threads {
                    self.flush(false)?;
                }
                self.pending.push(Vec::with_capacity(self.rows_per_chunk * width));
            }
            self.pending.last_mut().unwrap().extend_from_slice(row);
            self.rows_left = self.rows_left.saturating_sub(1);
        }
        Ok(())
    }

    /// Compresses the pending chunks in parallel and writes them; `last`
    /// ends the deflate stream with the final chunk.
    fn flush(&mut self, last: bool) -> std::io::Result<()> {
        let chunks = std::mem::take(&mut self.pending);
        let n = chunks.len();
        let (width, alpha) = (self.width, self.alpha);
        let parts: Vec<(Vec<u8>, usize, u32)> = raster::par_map(chunks.iter().enumerate(), |(i, px)| compress_chunk(px, width, alpha, last && i + 1 == n));
        for (idat, len, adler) in parts {
            self.out.write_all(&idat)?;
            self.adler = adler32_combine(self.adler, adler, len);
        }
        Ok(())
    }

    pub fn finish(mut self) -> std::io::Result<()> {
        if self.pending.is_empty() {
            // A page with no rows still needs a final deflate block.
            self.pending.push(Vec::new());
        }
        self.flush(true)?;
        self.out.write_all(&chunk(b"IDAT", &self.adler.to_be_bytes()))?;
        self.out.write_all(&chunk(b"IEND", &[]))?;
        self.out.flush()
    }
}

/// An in-memory `Write` target an `Encoder` can own.
#[derive(Clone, Default)]
pub struct SharedBuf(std::sync::Arc<std::sync::Mutex<Vec<u8>>>);

impl SharedBuf {
    pub fn take(&self) -> Vec<u8> {
        std::mem::take(&mut self.0.lock().unwrap())
    }
}

impl Write for SharedBuf {
    fn write(&mut self, buf: &[u8]) -> std::io::Result<usize> {
        self.0.lock().unwrap().extend_from_slice(buf);
        Ok(buf.len())
    }
    fn flush(&mut self) -> std::io::Result<()> {
        Ok(())
    }
}

/// Encodes a whole nativeRaster page (row-major from the top-left).
pub fn encode(width: u32, height: u32, pixels: &[u32], opts: &PngOptions) -> std::io::Result<Vec<u8>> {
    let out = SharedBuf::default();
    let mut enc = Encoder::new(out.clone(), width, height, opts)?;
    enc.write_rows(pixels)?;
    enc.finish()?;
    Ok(out.take())
}

/// Whether a page is opaque before any row is drawn: its first item clears
/// it to an opaque colour, and compositing over opaque pixels stays opaque.
pub fn opaque(list: &DisplayList) -> bool {
    matches!(list.items.first(), Some(Item::Clear(c)) if c[3] == 255)
}

/// Draws `list` and streams it to `out` as PNG, band by band as the
/// executor finishes them, so the page is never held whole.
pub fn render_png<W: Write + 'static>(list: &DisplayList, width: usize, height: usize, raster_opts: &Options, png_opts: &PngOptions, out: W) -> std::io::Result<()> {
    let mut enc = Encoder::new(out, width as u32, height as u32, png_opts)?;
    let mut err = None;
    raster::execute(list, width, height, raster_opts, |_, rows| {
        if err.is_none() {
            err = enc.write_rows(rows).err();
        }
    });
    if let Some(e) = err {
        return Err(e);
    }
    enc.finish()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::render::points::{Point, PointBatch};

    fn decode(bytes: &[u8]) -> (png::OutputInfo, Vec<u8>, Vec<(png::chunk::ChunkType, Vec<u8>)>) {
        let mut reader = png::Decoder::new(bytes).read_info().unwrap();
        let mut buf = vec![0; reader.output_buffer_size()];
        let info = reader.next_frame(&mut buf).unwrap();
        buf.truncate(info.buffer_size());
        // Chunk types and data, in file order.
        let mut chunks = Vec::new();
        let mut at = 8;
        while at < bytes.len() {
            let len = u32::from_be_bytes(bytes[at..at + 4].try_into().unwrap()) as usize;
            let ty = png::chunk::ChunkType(bytes[at + 4..at + 8].try_into().unwrap());
            chunks.push((ty, bytes[at + 8..at + 8 + len].to_vec()));
            at += 12 + len;
        }
        (info, buf, chunks)
    }

    #[test]
    fn writes_ragg_metadata_in_ragg_order() {
        let px = [0xFF0000FFu32, 0xFF00FF00, 0xFFFF0000, 0xFFFFFFFF, 0xFF000000, 0xFF808080];
        let bytes = encode(3, 2, &px, &PngOptions::for_background([255, 255, 255, 255], Some(150.0))).unwrap();
        let (info, buf, chunks) = decode(&bytes);
        assert_eq!(info.color_type, png::ColorType::Rgb);
        assert_eq!(&buf[..6], &[255, 0, 0, 0, 255, 0]);
        let types: Vec<_> = chunks.iter().map(|c| c.0).filter(|&t| t != png::chunk::IDAT).collect();
        assert_eq!(types, vec![png::chunk::IHDR, png::chunk::bKGD, png::chunk::pHYs, png::chunk::IEND]);
        assert_eq!(chunks[1].1, vec![0, 255, 0, 255, 0, 255]);
        // 150 dpi is 5905 px/m (0x1711), as ragg writes.
        assert_eq!(chunks[2].1, vec![0, 0, 0x17, 0x11, 0, 0, 0x17, 0x11, 1]);
    }

    #[test]
    fn transparent_backgrounds_give_rgba_and_premultiplied_bkgd() {
        let opts = PngOptions::for_background([0x33, 0x66, 0x99, 0x80], None);
        let bytes = encode(2, 1, &[0x80FF0000, 0xFF00FF00], &opts).unwrap();
        let (info, buf, chunks) = decode(&bytes);
        assert_eq!(info.color_type, png::ColorType::Rgba);
        assert_eq!(&buf[..8], &[0, 0, 255, 0x80, 0, 255, 0, 255]);
        // ragg's bKGD for #33669980.
        assert_eq!(chunks[1].1, vec![0, 0x1a, 0, 0x33, 0, 0x4d]);
        assert!(chunks.iter().all(|c| c.0 != png::chunk::pHYs));
    }

    #[test]
    fn adler_combines_like_one_pass() {
        let data: Vec<u8> = (0..100_000u32).map(|i| (i * 7919 % 251) as u8).collect();
        let (a, b) = data.split_at(37_123);
        assert_eq!(adler32_combine(adler32(a), adler32(b), b.len()), adler32(&data));
    }

    #[test]
    fn tall_pages_split_into_many_chunks_and_decode() {
        // 9000 rows of 300 px: about 16 chunks, so two parallel batches.
        let (w, h) = (300usize, 9000usize);
        let px: Vec<u32> = (0..w * h).map(|i| 0xFF00_0000 | (i as u32).wrapping_mul(2654435761) >> 8).collect();
        let bytes = encode(w as u32, h as u32, &px, &PngOptions::for_background([255; 4], None)).unwrap();
        let (_, buf, chunks) = decode(&bytes);
        assert!(chunks.iter().filter(|c| c.0 == png::chunk::IDAT).count() > 10);
        let want: Vec<u8> = px.iter().flat_map(|&p| [p as u8, (p >> 8) as u8, (p >> 16) as u8]).collect();
        assert_eq!(buf, want);
        // And an empty page.
        let bytes = encode(0, 0, &[], &PngOptions::for_background([255; 4], None)).unwrap();
        assert!(bytes.ends_with(&chunk(b"IEND", &[])));
    }

    #[test]
    fn streamed_pages_decode_to_the_canvas() {
        let pts: Vec<Point> = (0..3000)
            .map(|i| Point { x: (i * 37 % 301) as f64 + 0.4, y: (i * 53 % 211) as f64 + 0.2, shape: 19, size: 6.0, lwd: 1.0, col: [(i % 255) as u8, 60, 200, 120], fill: [0; 4] })
            .collect();
        for bg in [[255, 255, 255, 255], [0, 0, 0, 0]] {
            let mut list = DisplayList::new();
            list.push(Item::Clear(bg));
            list.push(Item::Points(PointBatch::new(&pts, 0)));
            let opts = Options { threads: 3, band_rows: 16 };
            let canvas = raster::render(&list, 301, 211, &opts);
            let png_opts = PngOptions::for_background(bg, Some(96.0));
            assert_eq!(png_opts.alpha, !opaque(&list));
            let out = SharedBuf::default();
            render_png(&list, 301, 211, &opts, &png_opts, out.clone()).unwrap();
            let (info, buf, _) = decode(&out.take());
            let want: Vec<u8> = if png_opts.alpha {
                canvas.iter().flat_map(|&p| p.to_le_bytes()).collect()
            } else {
                canvas.iter().flat_map(|&p| [p as u8, (p >> 8) as u8, (p >> 16) as u8]).collect()
            };
            assert_eq!((info.width, info.height), (301, 211));
            assert_eq!(buf, want);
        }
    }
}
