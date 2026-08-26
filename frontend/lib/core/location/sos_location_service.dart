import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

/// GPS snapshot captured when a patient triggers SOS.
class SosLocationSnapshot {
  const SosLocationSnapshot({
    required this.latitude,
    required this.longitude,
    required this.label,
  });

  final double latitude;
  final double longitude;
  final String label;
}

/// Reads device GPS (with consent) and reverse-geocodes a human label.
class SosLocationService {
  SosLocationService._();
  static final SosLocationService instance = SosLocationService._();

  Future<SosLocationSnapshot?> capture({required bool consent}) async {
    if (!consent) return null;

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return null;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }

    try {
      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: LocationSettings(
            accuracy: kIsWeb ? LocationAccuracy.medium : LocationAccuracy.high,
            timeLimit: Duration(seconds: kIsWeb ? 25 : 15),
          ),
        );
      } catch (_) {
        position = await Geolocator.getLastKnownPosition();
      }
      if (position == null) return null;

      final label = await _labelFor(position.latitude, position.longitude);

      return SosLocationSnapshot(
        latitude: position.latitude,
        longitude: position.longitude,
        label: label,
      );
    } catch (e) {
      debugPrint('SOS location capture failed: $e');
      return null;
    }
  }

  Future<String> _labelFor(double lat, double lng) async {
    try {
      final places = await placemarkFromCoordinates(lat, lng);
      if (places.isNotEmpty) {
        final p = places.first;
        final parts = <String>[
          if (p.subLocality != null && p.subLocality!.isNotEmpty)
            p.subLocality!,
          if (p.locality != null && p.locality!.isNotEmpty) p.locality!,
          if (p.administrativeArea != null && p.administrativeArea!.isNotEmpty)
            p.administrativeArea!,
        ];
        if (parts.isNotEmpty) {
          return parts.take(2).join(', ');
        }
      }
    } catch (_) {}

    return '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}';
  }
}
