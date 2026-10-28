/// Optional fields in the existing signed public runtime configuration.
/// Only bundled visual presets and poster assets can be selected remotely.
class PresentationConfig {
  final bool auroraEnabled, loginAdEnabled;
  final int doublePressMs, adSeconds;
  final double speed, borderWidth, glowSize, intensity;
  final String palette, style;
  const PresentationConfig({
    this.auroraEnabled = true,
    this.loginAdEnabled = true,
    this.doublePressMs = 360,
    this.adSeconds = 5,
    this.speed = 0.35,
    this.borderWidth = 3,
    this.glowSize = 28,
    this.intensity = 0.85,
    this.palette = 'intelligence',
    this.style = 'standard',
  });

  factory PresentationConfig.fromRuntime(Map<String, dynamic> data) {
    final root = data['presentation'] as Map? ?? const {};
    final aurora = root['aurora'] as Map? ?? const {};
    final ad = root['login_ad'] as Map? ?? const {};
    return PresentationConfig(
      auroraEnabled: aurora['enabled'] != false,
      loginAdEnabled: ad['enabled'] != false,
      doublePressMs: aurora['double_press_ms'] as int? ?? 360,
      adSeconds: ad['seconds'] as int? ?? 5,
      speed: (aurora['speed'] as num?)?.toDouble() ?? 0.35,
      borderWidth: (aurora['border_width'] as num?)?.toDouble() ?? 3,
      glowSize: (aurora['glow_size'] as num?)?.toDouble() ?? 28,
      intensity: (aurora['intensity'] as num?)?.toDouble() ?? 0.85,
      palette: aurora['palette'] as String? ?? 'intelligence',
      style: aurora['style'] as String? ?? 'standard',
    );
  }

  static void validate(Object? value) {
    if (value == null) return; // Existing signed revisions remain compatible.
    if (value is! Map ||
        value.keys.any((key) => !{'aurora', 'login_ad'}.contains(key))) {
      throw const FormatException('Presentation schema');
    }
    final aurora = value['aurora'];
    final ad = value['login_ad'];
    if (aurora != null) {
      if (aurora is! Map ||
          aurora.keys.any(
            (key) => !{
              'enabled',
              'double_press_ms',
              'speed',
              'border_width',
              'glow_size',
              'intensity',
              'palette',
              'style',
            }.contains(key),
          )) {
        throw const FormatException('Aurora schema');
      }
      _flag(aurora, 'enabled');
      _number(aurora, 'double_press_ms', 200, 600, integer: true);
      _number(aurora, 'speed', 0.05, 1);
      _number(aurora, 'border_width', 1, 8);
      _number(aurora, 'glow_size', 12, 48);
      _number(aurora, 'intensity', 0.2, 1);
      if (aurora.containsKey('palette') &&
          !{'intelligence', 'ocean', 'sunset'}.contains(aurora['palette'])) {
        throw const FormatException('Aurora palette');
      }
      if (aurora.containsKey('style') &&
          !{'subtle', 'standard', 'dramatic'}.contains(aurora['style'])) {
        throw const FormatException('Aurora style');
      }
    }
    if (ad != null) {
      if (ad is! Map ||
          ad.keys.any(
            (key) => !{'enabled', 'seconds', 'asset'}.contains(key),
          )) {
        throw const FormatException('Ad schema');
      }
      _flag(ad, 'enabled');
      _number(ad, 'seconds', 1, 5, integer: true);
      if (ad.containsKey('asset') && ad['asset'] != 'ai_assistant') {
        throw const FormatException('Ad asset');
      }
    }
  }

  static void _flag(Map map, String key) {
    if (map.containsKey(key) && map[key] is! bool) {
      throw FormatException('Presentation $key');
    }
  }

  static void _number(
    Map map,
    String key,
    num min,
    num max, {
    bool integer = false,
  }) {
    if (!map.containsKey(key)) return;
    final value = map[key];
    if (value is! num ||
        !value.isFinite ||
        value < min ||
        value > max ||
        (integer && value is! int)) {
      throw FormatException('Presentation $key');
    }
  }
}
