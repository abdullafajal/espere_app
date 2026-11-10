import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Disk + memory cache for avatar images (no extra packages needed).
///
/// * First load downloads the file once and stores it on disk.
/// * Next loads (even after an app restart / offline) read from disk.
/// * Decoded images are kept in Flutter's in-memory [ImageCache].
/// * Concurrent requests for the same URL share a single download.
class AvatarCache {
  AvatarCache._();

  static Directory? _dir;
  static final Map<String, Future<Uint8List?>> _inFlight = {};
  static const _maxAge = Duration(days: 30);

  static Future<Directory> _cacheDir() async {
    if (_dir != null) return _dir!;
    final base = await getTemporaryDirectory();
    final d = Directory('${base.path}/avatar_cache');
    if (!await d.exists()) await d.create(recursive: true);
    _dir = d;
    _prune(d);
    return d;
  }

  // Two 32-bit FNV-1a style hashes -> stable, filesystem-safe file name
  // (kept within 32-bit math so it also behaves on web).
  static String _name(String url) {
    var h1 = 0x811c9dc5;
    var h2 = 0x01000193;
    for (final c in url.codeUnits) {
      h1 = ((h1 ^ c) * 0x01000193) & 0xFFFFFFFF;
      h2 = ((h2 * 31) + c) & 0xFFFFFFFF;
    }
    return '${h1.toRadixString(16)}${h2.toRadixString(16)}_${url.length}';
  }

  static Future<void> _prune(Directory d) async {
    try {
      final cutoff = DateTime.now().subtract(_maxAge);
      await for (final f in d.list()) {
        if (f is File && (await f.lastModified()).isBefore(cutoff)) {
          await f.delete();
        }
      }
    } catch (_) {}
  }

  /// Returns the image bytes from disk, downloading them if needed.
  static Future<Uint8List?> load(String url) {
    return _inFlight.putIfAbsent(url, () async {
      try {
        final dir = await _cacheDir();
        final file = File('${dir.path}/${_name(url)}');
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          if (bytes.isNotEmpty) return bytes;
        }
        final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));
        if (res.statusCode != 200 || res.bodyBytes.isEmpty) return null;
        // Write atomically so a half-written file is never read.
        final tmp = File('${file.path}.tmp');
        await tmp.writeAsBytes(res.bodyBytes, flush: true);
        await tmp.rename(file.path);
        return res.bodyBytes;
      } catch (_) {
        return null;
      } finally {
        // allow retry after failure / completion
        unawaited(Future.microtask(() => _inFlight.remove(url)));
      }
    });
  }

  /// Download avatars in the background so they are ready before being shown.
  static void warmUp(Iterable<String?> urls) {
    for (final u in urls) {
      if (u != null && u.isNotEmpty) unawaited(load(u));
    }
  }

  /// Forget a URL (use after the user uploads a new avatar to the same URL).
  static Future<void> evict(String? url) async {
    if (url == null || url.isEmpty) return;
    try {
      final dir = await _cacheDir();
      final file = File('${dir.path}/${_name(url)}');
      if (await file.exists()) await file.delete();
    } catch (_) {}
    PaintingBinding.instance.imageCache.clear();
  }
}

/// ImageProvider backed by [AvatarCache].
class CachedAvatarProvider extends ImageProvider<CachedAvatarProvider> {
  final String url;
  const CachedAvatarProvider(this.url);

  @override
  Future<CachedAvatarProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<CachedAvatarProvider>(this);

  @override
  ImageStreamCompleter loadImage(
    CachedAvatarProvider key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _load(key, decode),
      scale: 1.0,
      debugLabel: key.url,
    );
  }

  Future<ui.Codec> _load(
    CachedAvatarProvider key,
    ImageDecoderCallback decode,
  ) async {
    final bytes = await AvatarCache.load(key.url);
    if (bytes == null || bytes.isEmpty) {
      // Not cached in imageCache so a later attempt can retry.
      PaintingBinding.instance.imageCache.evict(key);
      throw Exception('Failed to load avatar: ${key.url}');
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    return decode(buffer);
  }

  @override
  bool operator ==(Object other) =>
      other is CachedAvatarProvider && other.url == url;

  @override
  int get hashCode => url.hashCode;
}

/// Drop-in avatar image: cached, down-sampled to its display size, fades in,
/// and shows [fallback] while loading or if loading fails.
class CachedAvatarImage extends StatelessWidget {
  final String url;
  final double size;
  final BoxFit fit;
  final Widget fallback;

  const CachedAvatarImage({
    super.key,
    required this.url,
    required this.size,
    required this.fallback,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    final px = (size * MediaQuery.devicePixelRatioOf(context)).round();
    return SizedBox(
      width: size,
      height: size,
      child: Image(
        image: ResizeImage(CachedAvatarProvider(url), width: px, height: px),
        width: size,
        height: size,
        fit: fit,
        gaplessPlayback: true,
        frameBuilder: (context, child, frame, wasSync) {
          if (wasSync) return child;
          return Stack(
            fit: StackFit.expand,
            children: [
              fallback,
              AnimatedOpacity(
                opacity: frame == null ? 0 : 1,
                duration: const Duration(milliseconds: 180),
                child: child,
              ),
            ],
          );
        },
        errorBuilder: (_, __, ___) => fallback,
      ),
    );
  }
}
