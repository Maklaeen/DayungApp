import 'package:supabase_flutter/supabase_flutter.dart';

String buildStorageRef(String bucket, String objectPath) {
  final normalizedBucket = bucket.trim().replaceAll(RegExp(r'^/+|/+$'), '');
  final normalizedPath = objectPath.trim().replaceAll(RegExp(r'^/+'), '');
  return '$normalizedBucket/$normalizedPath';
}

Future<String?> resolveSupabaseStorageUrl(
  String raw, {
  SupabaseClient? client,
  int expiresInSeconds = 3600,
}) async {
  final value = raw.trim();
  if (value.isEmpty) return null;

  final supabase = client ?? Supabase.instance.client;
  final location = _parseStorageLocation(value);

  if (location != null) {
    try {
      // Always use signed URL for private buckets
      final signedUrl = await supabase.storage
          .from(location.bucket)
          .createSignedUrl(location.objectPath, expiresInSeconds);
      return signedUrl;
    } catch (e) {
      // Log the error for debugging
      // ignore: avoid_print
      print(
        'Error creating signed URL for ${location.bucket}/${location.objectPath}: $e',
      );
      return null;
    }
  }

  // Do not pass through arbitrary URLs: sensitive document buckets are private.
  // Callers must use a bucket/object path or a recognized Supabase storage URL
  // so the object is always served through a short-lived signed URL.
  return null;
}

bool storageLooksLikePdf(String raw) =>
    _normalizedPath(raw).toLowerCase().endsWith('.pdf');

bool storageLooksLikeImage(String raw) {
  final path = _normalizedPath(raw).toLowerCase();
  return path.endsWith('.jpg') ||
      path.endsWith('.jpeg') ||
      path.endsWith('.png') ||
      path.endsWith('.gif') ||
      path.endsWith('.webp');
}

String _normalizedPath(String raw) {
  final value = raw.trim();
  final uri = Uri.tryParse(value);
  if (uri != null && uri.hasScheme) {
    return uri.path;
  }
  return value;
}

_StorageLocation? _parseStorageLocation(String raw) {
  final direct = _parseBucketPath(raw);
  if (direct != null) return direct;

  final uri = Uri.tryParse(raw);
  if (uri == null || !uri.hasScheme) return null;

  final segments = uri.pathSegments;
  if (segments.isEmpty) return null;

  for (final marker in const ['public', 'sign', 'authenticated']) {
    final markerIndex = segments.indexOf(marker);
    if (markerIndex >= 0 && markerIndex + 2 < segments.length) {
      final bucket = segments[markerIndex + 1];
      final objectPath = segments.sublist(markerIndex + 2).join('/');
      if (bucket.isNotEmpty && objectPath.isNotEmpty) {
        return _StorageLocation(bucket, Uri.decodeComponent(objectPath));
      }
    }
  }

  return null;
}

_StorageLocation? _parseBucketPath(String raw) {
  final value = raw.trim().replaceFirst(RegExp(r'^/+'), '');
  if (value.isEmpty) return null;

  // Absolute URLs must be parsed from their storage path, not as bucket refs.
  final uri = Uri.tryParse(value);
  if (uri != null && uri.hasScheme) return null;

  final segments = value.split('/');
  if (segments.length < 2) return null;

  final bucket = segments.first.trim();
  final objectPath = segments.sublist(1).join('/').trim();
  if (bucket.isEmpty || objectPath.isEmpty) return null;

  return _StorageLocation(bucket, objectPath);
}

class _StorageLocation {
  const _StorageLocation(this.bucket, this.objectPath);

  final String bucket;
  final String objectPath;
}
