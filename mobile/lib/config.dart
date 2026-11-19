/// URL API diset saat build: `flutter build apk --dart-define=API_BASE=https://app.<domain>/api/v1`.
/// Nilai bawaan = server dev di PC lewat `adb reverse tcp:8010 tcp:8010`.
const apiBase = String.fromEnvironment('API_BASE', defaultValue: 'http://127.0.0.1:8010/api/v1');

/// Samakan dengan `version` di pubspec.yaml (bagian sebelum tanda +). Dikirim di header X-App-Version.
const appVersion = '1.0.0';
