import 'package:flutter/services.dart';

import '../../domain/telemetry/telemetry_dependencies.dart';

class AndroidRotationVectorHeadingDataSource implements HeadingDataSource {
  static const _channel =
      EventChannel('speedometer/rotation_vector_heading/events');
  static const _methods =
      MethodChannel('speedometer/rotation_vector_heading/methods');

  @override
  Stream<HeadingSensorSample> get samples =>
      _channel.receiveBroadcastStream().map((event) {
        final values = Map<Object?, Object?>.from(event as Map);
        return HeadingSensorSample(
          degrees: (values['degrees'] as num).toDouble(),
          accuracy: (values['accuracy'] as num).toInt(),
        );
      });

  @override
  Future<bool> isAvailable() async =>
      await _methods.invokeMethod<bool>('isAvailable') ?? false;

  @override
  Future<void> updateLocation(TelemetrySample sample) =>
      _methods.invokeMethod<void>('setLocation', {
        'latitude': sample.latitude,
        'longitude': sample.longitude,
      });
}
