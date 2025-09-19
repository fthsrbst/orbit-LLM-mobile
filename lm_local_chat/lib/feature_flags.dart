/// Centralised feature toggles for the application.
///
/// Feature flags let us enable or disable larger areas of functionality
/// without having to touch individual call sites each time.
class FeatureFlags {
  const FeatureFlags._();

  /// Controls the availability of the "star" experience.
  ///
  /// When disabled the UI hides star specific entry points and any persisted
  /// preferences that refer to it fall back to the default orbit mode.
  static const bool starModeEnabled = false;
}
