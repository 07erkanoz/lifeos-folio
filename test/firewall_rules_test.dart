import 'package:evrak_convert/services/office/office_network.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'the firewall is opened from the local networks only, on Folio’s port',
    () {
      final rules = OfficeNetwork.firewallRules(48001);
      expect(rules, hasLength(6));
      for (final r in rules) {
        expect(
          r,
          matches(
            RegExp(
              r'^ufw allow from (10\.0\.0\.0/8|172\.16\.0\.0/12|192\.168\.0\.0/16) '
              r'to any port (48001 proto tcp|5353 proto udp)$',
            ),
          ),
        );
      }
    },
  );
}
