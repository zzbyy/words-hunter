//! Audio feedback: plays a short "pop" sound on word capture.
//! Uses the rodio crate. Bundled .wav or .ogg file in app resources.

use std::io::Cursor;
use rodio::{Decoder, OutputStream, source::Source};
use tracing::{debug, warn, error};

/// Built-in pop sound as raw bytes (short sine wave burst)
/// This is a ~100ms "pop" sound at 800Hz, generated programmatically
/// as a fallback when no audio file is bundled.
const POP_SOUND_WAV: &[u8] = include_bytes!("../assets/pop.wav");

pub fn play_pop() {
    std::thread::spawn(|| {
        if let Err(e) = play_pop_inner() {
            warn!("Failed to play pop sound: {:?}", e);
        }
    });
}

fn play_pop_inner() -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let (_stream, stream_handle) = OutputStream::try_default()?;

    let cursor = Cursor::new(POP_SOUND_WAV);
    let source = Decoder::new(cursor)?;
    stream_handle.play_raw(source.convert_samples())?;

    debug!("Pop sound played");
    Ok(())
}
