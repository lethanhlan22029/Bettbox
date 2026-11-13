import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class MetronSessionStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecureMetronSessionStore implements MetronSessionStore {
  const SecureMetronSessionStore();

  // Ad-hoc macOS builds have no provisioning profile for Keychain Sharing.
  static const _storage = FlutterSecureStorage(
    mOptions: MacOsOptions(usesDataProtectionKeychain: false),
  );

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}
