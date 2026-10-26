/// Habaynta app-ka.
///
/// QAYBTA 1 (hadda): USE_MOCK=true. App-ku wuxuu ku shaqeeyaa xog tijaabo ah
/// oo telefoonka ku kaydsan, backend looma baahna.
///
/// QAYBTA 2 (backend): ku xir server-ka dhabta ah:
///   flutter run --dart-define=USE_MOCK=false --dart-define=API_URL=http://10.0.2.2:3000
///
/// API_URL:
/// - Android emulator (debug): http://10.0.2.2:3000
/// - iOS simulator: HTTPS endpoint (ATS blocks local HTTP by default)
/// - Release builds: HTTPS endpoint ayaa waajib ah
/// - Telefoon dhab ah (debug Android): http://<IP-ga kombiyuutarkaaga>:3000
class AppConfig {
  static const useMock = bool.fromEnvironment('USE_MOCK', defaultValue: true);
  static const apiUrl = String.fromEnvironment('API_URL', defaultValue: 'http://10.0.2.2:3000');
}
