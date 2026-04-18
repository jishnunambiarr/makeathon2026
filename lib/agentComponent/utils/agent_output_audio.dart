import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

/// Estimates normalized amplitude (0.0–1.0) from a base64 chunk.
///
/// ElevenLabs sends agent TTS audio in `onAudio` as base64; this assumes
/// **16-bit little-endian PCM** (common for voice). If your stream format
/// differs, adjust this helper.
double amplitudeFromAgentAudioBase64(String base64Chunk) {
  if (base64Chunk.isEmpty) return 0;
  Uint8List bytes;
  try {
    bytes = base64Decode(base64Chunk);
  } catch (_) {
    return 0;
  }
  return pcm16LeRmsNormalized(bytes);
}

/// RMS of signed 16-bit LE samples, mapped to ~0–1 for UI meters.
double pcm16LeRmsNormalized(Uint8List bytes) {
  if (bytes.length < 2) return 0;
  final bd = ByteData.sublistView(bytes);
  final sampleCount = bytes.length ~/ 2;
  if (sampleCount == 0) return 0;

  var sumSq = 0.0;
  for (var i = 0; i < sampleCount; i++) {
    final s = bd.getInt16(i * 2, Endian.little) / 32768.0;
    sumSq += s * s;
  }
  final rms = math.sqrt(sumSq / sampleCount);
  // Gentle boost so quiet speech still moves the avatar; clamp for Rive input.
  return (rms * 4.0).clamp(0.0, 1.0);
}
