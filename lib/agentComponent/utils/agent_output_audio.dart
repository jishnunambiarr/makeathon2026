import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

/// Normalized amplitude (0.0–1.0) from one `onAudio` base64 chunk (16-bit LE PCM).
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
  // Slight gain for UI visibility; clamped for Rive `audioLevel` input.
  return (rms * 4.0).clamp(0.0, 1.0);
}
