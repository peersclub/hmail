/// Draws NoMail's app icon and writes the full iOS icon set.
///
/// Run with:  flutter test tool/generate_app_icon.dart
///
/// A generator rather than a checked-in binary because the icon *is* the design
/// system: the field is the same near-black wash `GlassBackground` paints, the
/// ambient glow is the same one behind every screen, and the mark is the same
/// sun the Today tab and the sign-in screen already use. When the palette
/// changes, this regenerates instead of drifting.
///
/// Why a sun and not an envelope: the product is not "email, blocked" — it is
/// the morning glance that replaces reading email. An envelope with a line
/// through it would advertise the thing NoMail removes rather than the thing it
/// gives you. The sun is already the app's mark for Today; the home screen
/// should say the same word as the first tab.
///
/// Monochrome on purpose. The whole design system is ink on paper — `accent` is
/// near-white on dark and near-black on light, never a hue — and an icon in a
/// colour the app never uses would be the one place the product lies about
/// itself. It also reads well beside colourful icons rather than competing.
///
/// No text in the icon, per Apple's guidance, and drawn full-bleed: iOS applies
/// the squircle mask and any shadow itself.
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

/// Every file the asset catalogue asks for, and the pixel size it must be.
/// Keep in step with `AppIcon.appiconset/Contents.json`.
const _targets = <String, int>{
  'Icon-App-20x20@1x.png': 20,
  'Icon-App-20x20@2x.png': 40,
  'Icon-App-20x20@3x.png': 60,
  'Icon-App-29x29@1x.png': 29,
  'Icon-App-29x29@2x.png': 58,
  'Icon-App-29x29@3x.png': 87,
  'Icon-App-40x40@1x.png': 40,
  'Icon-App-40x40@2x.png': 80,
  'Icon-App-40x40@3x.png': 120,
  'Icon-App-60x60@2x.png': 120,
  'Icon-App-60x60@3x.png': 180,
  'Icon-App-76x76@1x.png': 76,
  'Icon-App-76x76@2x.png': 152,
  'Icon-App-83.5x83.5@2x.png': 167,
  'Icon-App-1024x1024@1x.png': 1024,
};

const _outputDir = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';

/// The app's dark backdrop, from `Palette.backdropTop`/`backdropBottom`.
const _fieldTop = Color(0xFF0A0C12);
const _fieldBottom = Color(0xFF16191F);

/// `Palette.accent` in dark mode — the ink the app draws with.
const _ink = Color(0xFFF2F3F5);

typedef Color = ui.Color;

/// Paints the icon into [canvas] at [size] pixels square.
///
/// Everything is expressed as a fraction of [size] so a 20pt icon is the same
/// drawing as the 1024pt one, not a shrunken variant that loses its centre.
void paintIcon(ui.Canvas canvas, double size) {
  final square = ui.Rect.fromLTWH(0, 0, size, size);

  // Field: the same top-to-bottom wash as GlassBackground in dark mode.
  canvas.drawRect(
    square,
    ui.Paint()
      ..shader = ui.Gradient.linear(
        ui.Offset(size / 2, 0),
        ui.Offset(size / 2, size),
        const [_fieldTop, _fieldBottom],
      ),
  );

  // Ambient glow, top-right, mirroring the accent glow on every screen. Very
  // low alpha: at 20px it should read as a faint lift, never as a blob.
  canvas.drawCircle(
    ui.Offset(size * 0.82, size * 0.16),
    size * 0.62,
    ui.Paint()
      ..shader = ui.Gradient.radial(
        ui.Offset(size * 0.82, size * 0.16),
        size * 0.62,
        [
          _ink.withValues(alpha: 0.10),
          _ink.withValues(alpha: 0.0),
        ],
      ),
  );

  final centre = ui.Offset(size / 2, size / 2);
  final ink = ui.Paint()
    ..color = _ink
    ..isAntiAlias = true;

  // Eight rays before the disc, so the disc's edge stays clean where they meet.
  // Round caps and a gap from the disc keep it legible when the whole icon is
  // 20 pixels wide — the size at which most icon designs fall apart.
  final rayPaint = ui.Paint()
    ..color = _ink
    ..strokeWidth = size * 0.052
    ..strokeCap = ui.StrokeCap.round
    ..isAntiAlias = true;

  const rays = 8;
  final inner = size * 0.255;
  final outer = size * 0.355;
  for (var i = 0; i < rays; i++) {
    final angle = (math.pi * 2 / rays) * i - math.pi / 2;
    canvas.drawLine(
      centre + ui.Offset(math.cos(angle) * inner, math.sin(angle) * inner),
      centre + ui.Offset(math.cos(angle) * outer, math.sin(angle) * outer),
      rayPaint,
    );
  }

  canvas.drawCircle(centre, size * 0.168, ink);
}

Future<Uint8List> _render(int pixels) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  paintIcon(canvas, pixels.toDouble());
  final image = await recorder.endRecording().toImage(pixels, pixels);
  // Raw pixels, not Flutter's PNG encoder: that always writes RGBA, and App
  // Store Connect rejects an app icon that merely *has* an alpha channel even
  // when every pixel in it is opaque. Encoding RGB ourselves makes the
  // committed assets valid by construction instead of by a post-process step
  // someone forgets to run.
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return _encodeOpaquePng(data!.buffer.asUint8List(), pixels);
}

/// Minimal PNG writer: 8-bit truecolour (colour type 2), no alpha.
///
/// Alpha is dropped rather than composited — the drawing is opaque everywhere,
/// so each pixel's RGB is already its final colour.
Uint8List _encodeOpaquePng(Uint8List rgba, int size) {
  // Scanlines with a leading filter byte of 0 (None). Filtering would compress
  // better; an icon is a few hundred KB at worst and clarity wins.
  final raw = BytesBuilder();
  for (var y = 0; y < size; y++) {
    raw.addByte(0);
    for (var x = 0; x < size; x++) {
      final i = (y * size + x) * 4;
      raw..addByte(rgba[i])..addByte(rgba[i + 1])..addByte(rgba[i + 2]);
    }
  }

  final out = BytesBuilder()
    ..add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);

  final ihdr = BytesBuilder()
    ..add(_be32(size))
    ..add(_be32(size))
    ..addByte(8) // bit depth
    ..addByte(2) // colour type: truecolour, no alpha
    ..addByte(0) // deflate
    ..addByte(0) // adaptive filtering
    ..addByte(0); // no interlace
  out.add(_chunk('IHDR', ihdr.takeBytes()));
  out.add(_chunk('IDAT', Uint8List.fromList(zlib.encode(raw.takeBytes()))));
  out.add(_chunk('IEND', Uint8List(0)));
  return out.takeBytes();
}

Uint8List _chunk(String type, Uint8List body) {
  final typeBytes = Uint8List.fromList(type.codeUnits);
  final crcInput = Uint8List(typeBytes.length + body.length)
    ..setRange(0, typeBytes.length, typeBytes)
    ..setRange(typeBytes.length, typeBytes.length + body.length, body);
  return Uint8List.fromList([
    ..._be32(body.length),
    ...typeBytes,
    ...body,
    ..._be32(_crc32(crcInput)),
  ]);
}

List<int> _be32(int value) =>
    [(value >> 24) & 0xFF, (value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF];

final List<int> _crcTable = List<int>.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

int _crc32(Uint8List bytes) {
  var crc = 0xFFFFFFFF;
  for (final byte in bytes) {
    crc = _crcTable[(crc ^ byte) & 0xFF] ^ (crc >> 8);
  }
  return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

void main() {
  test('writes the iOS app icon set', () async {
    final dir = Directory(_outputDir);
    expect(dir.existsSync(), isTrue,
        reason: 'run from the repo root: $_outputDir must exist');

    for (final target in _targets.entries) {
      final bytes = await _render(target.value);
      File('$_outputDir/${target.key}').writeAsBytesSync(bytes);
      // ignore: avoid_print
      print('wrote ${target.key} (${target.value}px, ${bytes.length} bytes)');
    }

    // The marketing icon is the one App Store Connect rejects hardest: it must
    // be exactly 1024x1024 and fully opaque.
    final marketing =
        File('$_outputDir/Icon-App-1024x1024@1x.png').readAsBytesSync();
    expect(marketing.length, greaterThan(1000));
  });
}
