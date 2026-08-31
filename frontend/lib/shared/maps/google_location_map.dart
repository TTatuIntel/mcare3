import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/env/app_env.dart';
import '../../core/location/google_maps_loader.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// A bounded, privacy-conscious map for a location the API has already
/// authorized the current user to see. It never asks for the viewer's own
/// location and renders only when the platform SDK configuration is enabled.
class GoogleLocationMap extends StatefulWidget {
  const GoogleLocationMap({
    super.key,
    required this.latitude,
    required this.longitude,
    this.label = 'Patient location',
    this.height = 220,
  });

  final double latitude;
  final double longitude;
  final String label;
  final double height;

  @override
  State<GoogleLocationMap> createState() => _GoogleLocationMapState();
}

class _GoogleLocationMapState extends State<GoogleLocationMap> {
  late final Future<bool> _ready = ensureGoogleMapsLoaded(
    AppEnv.googleMapsWebApiKey,
  );

  @override
  Widget build(BuildContext context) {
    if (!AppEnv.embeddedGoogleMapsEnabled) return const SizedBox.shrink();

    return FutureBuilder<bool>(
      future: _ready,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return _MapFrame(
            height: widget.height,
            child: const Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.data != true) {
          return _MapFrame(
            height: widget.height,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Text(
                  'The embedded map could not load. Open Google Maps below.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppPalette.textMuted(context),
                  ),
                ),
              ),
            ),
          );
        }

        final target = LatLng(widget.latitude, widget.longitude);
        return _MapFrame(
          height: widget.height,
          child: GoogleMap(
            initialCameraPosition: CameraPosition(target: target, zoom: 15),
            markers: {
              Marker(
                markerId: const MarkerId('patient-location'),
                position: target,
                infoWindow: InfoWindow(title: widget.label),
              ),
            },
            mapToolbarEnabled: true,
            myLocationButtonEnabled: false,
            myLocationEnabled: false,
            zoomControlsEnabled: false,
            compassEnabled: true,
          ),
        );
      },
    );
  }
}

class _MapFrame extends StatelessWidget {
  const _MapFrame({required this.height, required this.child});

  final double height;
  final Widget child;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppPalette.surfaceAlt(context),
          border: Border.all(color: AppPalette.border(context)),
        ),
        child: child,
      ),
    ),
  );
}
