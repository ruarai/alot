//! PNG encoding for rendered pages. ragg's PNG writer (libpng at its
//! default zlib level) costs more than drawing a busy plot, so `alot_png()`
//! draws on a capture device and encodes here with fdeflate's fast mode.

/// Encodes nativeRaster pixels (`R | G << 8 | B << 16 | A << 24`, row-major
/// from the top-left) as an 8-bit PNG. As ragg's `agg_png()` does
/// (src/png_dev.cpp), the PNG is RGBA when `alpha` (the device background is
/// not opaque) and RGB otherwise, dropping the alpha channel. With `dpi`,
/// it carries ragg's `pHYs` chunk (src/AggDevicePng.h): `dpi / 0.0254`
/// pixels per metre, truncated.
pub fn encode(width: u32, height: u32, pixels: &[u32], alpha: bool, dpi: Option<f64>) -> Result<Vec<u8>, png::EncodingError> {
    let opaque = !alpha;
    let data: Vec<u8> = if opaque {
        pixels.iter().flat_map(|&p| [p as u8, (p >> 8) as u8, (p >> 16) as u8]).collect()
    } else {
        pixels.iter().flat_map(|&p| p.to_le_bytes()).collect()
    };
    let mut out = Vec::new();
    {
        let mut enc = png::Encoder::new(&mut out, width, height);
        enc.set_color(if opaque { png::ColorType::Rgb } else { png::ColorType::Rgba });
        enc.set_depth(png::BitDepth::Eight);
        enc.set_compression(png::Compression::Fast);
        if let Some(dpi) = dpi {
            let ppm = (dpi / 0.0254) as u32;
            enc.set_pixel_dims(Some(png::PixelDimensions { xppu: ppm, yppu: ppm, unit: png::Unit::Meter }));
        }
        let mut writer = enc.write_header()?;
        writer.write_image_data(&data)?;
    }
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn round_trips() {
        let px = [0xFF0000FFu32, 0xFF00FF00, 0xFFFF0000, 0xFFFFFFFF, 0xFF000000, 0xFF808080];
        let bytes = encode(3, 2, &px, false, Some(300.0)).unwrap();
        let mut reader = png::Decoder::new(&bytes[..]).read_info().unwrap();
        let dims = reader.info().pixel_dims.unwrap();
        assert_eq!((dims.xppu, dims.yppu, dims.unit), (11811, 11811, png::Unit::Meter));
        let mut buf = vec![0; reader.output_buffer_size()];
        let info = reader.next_frame(&mut buf).unwrap();
        assert_eq!(info.color_type, png::ColorType::Rgb);
        assert_eq!(&buf[..info.buffer_size()][..6], &[255, 0, 0, 0, 255, 0]);
    }

    #[test]
    fn alpha_follows_the_background() {
        let px = [0x80FF0000u32, 0xFF00FF00];
        let bytes = encode(2, 1, &px, true, None).unwrap();
        let mut reader = png::Decoder::new(&bytes[..]).read_info().unwrap();
        assert!(reader.info().pixel_dims.is_none());
        let mut buf = vec![0; reader.output_buffer_size()];
        let info = reader.next_frame(&mut buf).unwrap();
        assert_eq!(info.color_type, png::ColorType::Rgba);
        assert_eq!(&buf[..8], &[0, 0, 255, 0x80, 0, 255, 0, 255]);
    }
}
