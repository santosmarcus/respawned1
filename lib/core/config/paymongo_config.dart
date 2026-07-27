import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/donation/paymongo_service.dart';

class PayMongoConfig {
  /// The Paymongo Public Key. 
  /// For production, consider using --dart-define or a .env file.
  static const String publicKey = String.fromEnvironment(
    'PAYMONGO_PUBLIC_KEY',
    defaultValue: 'pk_test_6noyvzxvVgfXrQGkGLQD5Tut',
  );

  static const bool isTestMode = bool.fromEnvironment(
    'PAYMONGO_TEST_MODE',
    defaultValue: true,
  );
}

final payMongoServiceProvider = Provider<PayMongoService>((ref) {
  return PayMongoService(
    publicKey: PayMongoConfig.publicKey,
    isTestMode: PayMongoConfig.isTestMode,
  );
});
