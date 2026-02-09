import 'package:flutter_test/flutter_test.dart';
import 'package:deflockapp/services/network_status.dart';

void main() {
  group('NetworkStatus', () {
    late NetworkStatus networkStatus;

    setUp(() {
      networkStatus = NetworkStatus.instance;
      networkStatus.clear(); // Start clean for each test
    });

    test('starts with idle status', () {
      expect(networkStatus.status, NetworkRequestStatus.idle);
    });

    test('transitions through loading states correctly', () {
      networkStatus.setLoading();
      expect(networkStatus.status, NetworkRequestStatus.loading);
      
      networkStatus.setSplitting();
      expect(networkStatus.status, NetworkRequestStatus.splitting);
      
      networkStatus.setSuccess();
      expect(networkStatus.status, NetworkRequestStatus.success);
    });

    test('handles error states correctly', () {
      networkStatus.setTimeout();
      expect(networkStatus.status, NetworkRequestStatus.timeout);
      
      networkStatus.setRateLimited();
      expect(networkStatus.status, NetworkRequestStatus.rateLimited);
      
      networkStatus.setError();
      expect(networkStatus.status, NetworkRequestStatus.error);
      
      networkStatus.setNoData();
      expect(networkStatus.status, NetworkRequestStatus.noData);
    });

    test('clear() resets to idle', () {
      networkStatus.setError();
      expect(networkStatus.status, NetworkRequestStatus.error);
      
      networkStatus.clear();
      expect(networkStatus.status, NetworkRequestStatus.idle);
    });
    
    test('auto-reset timers work (success)', () async {
      networkStatus.setSuccess();
      expect(networkStatus.status, NetworkRequestStatus.success);
      
      // Wait for auto-reset (2 seconds + buffer)
      await Future.delayed(const Duration(milliseconds: 2100));
      expect(networkStatus.status, NetworkRequestStatus.idle);
    });
  });
}