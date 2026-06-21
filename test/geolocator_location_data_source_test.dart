import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:speedometer/data/location/geolocator_location_data_source.dart';

void main() {
  test('solicita atualizações de navegação a cada 500 milissegundos', () {
    final settings = GeolocatorLocationDataSource.locationSettings;

    expect(settings.accuracy, LocationAccuracy.bestForNavigation);
    expect(settings.distanceFilter, 0);
    expect(settings.intervalDuration, const Duration(milliseconds: 500));
  });
}
