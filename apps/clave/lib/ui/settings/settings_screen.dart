import 'package:flutter/material.dart';

import '../../core/app_info.dart';
import '../../core/app_scope.dart';
import '../../core/settings.dart';
import '../legal/legal_document.dart';
import '../widgets/adaptive.dart';
import 'latency_calibration_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final Services s = AppScope.of(context);
    final AppSettings st = s.settings;
    final bool spanish = isSpanish(context);
    final ColorScheme cs = Theme.of(context).colorScheme;
    void save() {
      st.save();
      setState(() {});
    }

    return Scaffold(
      appBar: AppBar(title: Text(t(context, 'Ajustes', 'Settings'))),
      body: ReadableWidth(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: <Widget>[
            _header(context, t(context, 'General', 'General')),
            ListTile(
              title: Text(t(context, 'Idioma', 'Language')),
              subtitle: _left(SegmentedButton<String>(
                segments: const <ButtonSegment<String>>[ButtonSegment<String>(value: 'es', label: Text('Español')), ButtonSegment<String>(value: 'en', label: Text('English'))],
                selected: <String>{st.language},
                showSelectedIcon: false,
                onSelectionChanged: (Set<String> v) {
                  st.setLanguage(v.first);
                  save();
                },
              )),
            ),
            ListTile(
              title: Text(t(context, 'Tema', 'Theme')),
              subtitle: _left(SegmentedButton<String>(
                segments: <ButtonSegment<String>>[
                  ButtonSegment<String>(value: 'system', label: Text(t(context, 'Sistema', 'System'))),
                  ButtonSegment<String>(value: 'light', label: Text(t(context, 'Claro', 'Light'))),
                  ButtonSegment<String>(value: 'dark', label: Text(t(context, 'Oscuro', 'Dark'))),
                ],
                selected: <String>{st.themeMode},
                showSelectedIcon: false,
                onSelectionChanged: (Set<String> v) {
                  st.themeMode = v.first;
                  save();
                },
              )),
            ),
            SwitchListTile(
              title: Text(t(context, 'Mantener la pantalla encendida', 'Keep the screen on')),
              subtitle: Text(t(context, 'En el afinador, el metrónomo y el tono, y mientras se graba una toma.', 'In the tuner, the metronome and the drone, and while a take is recording.')),
              value: st.keepAwake,
              onChanged: (bool v) {
                st.keepAwake = v;
                save();
              },
            ),
            _header(context, t(context, 'Metrónomo', 'Metronome')),
            SwitchListTile(
              title: Text(t(context, 'Vibrar en cada pulso', 'Vibrate on each beat')),
              subtitle: Text(t(context, 'Pulsos cortos; el acento vibra más fuerte. Necesita un teléfono con vibración.', 'Short pulses; the accent vibrates harder. Needs a phone that can vibrate.')),
              value: st.haptics,
              onChanged: (bool v) {
                st.haptics = v;
                save();
              },
            ),
            SwitchListTile(
              title: Text(t(context, 'Destello de pantalla', 'Screen flash')),
              subtitle: Text(t(context, 'Un destello suave del fondo en cada pulso, como mucho tres por segundo: a tempos rápidos solo en el acento y, si tampoco así cabe, no destella. No se usa si el sistema pide quitar animaciones.', 'A soft background flash on each beat, at most three per second: at fast tempos only on the accent, and if even that does not fit, no flash. Off when the system asks to remove animations.')),
              value: st.flash,
              onChanged: (bool v) {
                st.flash = v;
                save();
              },
            ),
            SwitchListTile(
              title: Text(t(context, 'Conteo hablado en el primer compás', 'Spoken count-in on the first bar')),
              subtitle: Text(t(context, 'Usa la voz del sistema; puede sonar un poco después del clic.', 'Uses the system voice; it may lag the click slightly.')),
              value: st.countInVoice,
              onChanged: (bool v) {
                st.countInVoice = v;
                save();
              },
            ),
            ListTile(
              title: Text(t(context, 'Volumen del clic', 'Click volume')),
              trailing: Text(formatPercent(st.metronomeVolume, spanish: spanish)),
              subtitle: Slider(
                value: st.metronomeVolume.clamp(0.0, 1.0),
                semanticFormatterCallback: (double v) => formatPercent(v, spanish: spanish),
                onChanged: (double v) {
                  st.metronomeVolume = v;
                  save();
                },
              ),
            ),
            ListTile(
              title: Text(t(context, 'Retraso del audio', 'Audio delay')),
              trailing: Text('${st.audioDelayMs} ms', style: const TextStyle(fontFeatures: <FontFeature>[FontFeature.tabularFigures()])),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(t(
                    context,
                    'Cuánto tarda en oírse el clic. La animación y la vibración se retrasan lo mismo para ir con lo que oyes. Sin audífonos suele bastar 0 ms; con audífonos Bluetooth, de 150 a 300 ms.',
                    'How long the click takes to be heard. The animation and vibration are delayed by the same amount to match what you hear. Without headphones 0 ms is usually right; with Bluetooth headphones, 150 to 300 ms.',
                  )),
                  Slider(
                    min: 0,
                    max: AppSettings.maxAudioDelayMs.toDouble(),
                    divisions: AppSettings.maxAudioDelayMs ~/ 10,
                    value: st.audioDelayMs.toDouble().clamp(0.0, AppSettings.maxAudioDelayMs.toDouble()),
                    label: '${st.audioDelayMs} ms',
                    semanticFormatterCallback: (double v) => '${v.round()} ms',
                    onChanged: (double v) {
                      st.audioDelayMs = v.round();
                      save();
                    },
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        await Navigator.of(context).push<int>(MaterialPageRoute<int>(builder: (_) => const LatencyCalibrationScreen()));
                        if (mounted) {
                          setState(() {});
                        }
                      },
                      icon: const Icon(Icons.touch_app_rounded),
                      label: Text(t(context, 'Calibrar con toques', 'Calibrate by tapping')),
                    ),
                  ),
                ],
              ),
            ),
            _header(context, t(context, 'Grabadora', 'Recorder')),
            ListTile(
              title: Text(t(context, 'Formato', 'Format')),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(t(context, 'AAC ocupa poco; WAV y FLAC no pierden calidad.', 'AAC is small; WAV and FLAC are lossless.')),
                  const SizedBox(height: 6),
                  SegmentedButton<String>(
                    segments: const <ButtonSegment<String>>[ButtonSegment<String>(value: 'aac', label: Text('AAC')), ButtonSegment<String>(value: 'wav', label: Text('WAV')), ButtonSegment<String>(value: 'flac', label: Text('FLAC'))],
                    selected: <String>{st.recordingFormat},
                    showSelectedIcon: false,
                    onSelectionChanged: (Set<String> v) {
                      st.recordingFormat = v.first;
                      save();
                    },
                  ),
                ],
              ),
            ),
            _header(context, t(context, 'Acerca de', 'About')),
            ListTile(
              title: const Text('$kAppName $kAppVersion'),
              subtitle: Text(
                t(
                  context,
                  'Gratis, sin anuncios, sin cuenta y sin internet. Los datos quedan en tu dispositivo. Código Apache-2.0; motor de audio flutter_soloud (MIT).',
                  'Free, no ads, no account and no internet. Your data stays on your device. Code Apache-2.0; audio engine flutter_soloud (MIT).',
                ),
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.privacy_tip_outlined),
              title: Text(t(context, 'Política de privacidad', 'Privacy policy')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PrivacyPolicyScreen(spanish: AppScope.of(context).settings.spanish))),
            ),
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: Text(t(context, 'Licencias de código abierto', 'Open-source licenses')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showLicensePage(context: context, applicationName: kAppName, applicationVersion: kAppVersion),
            ),
          ],
        ),
      ),
    );
  }

  Widget _left(Widget child) => Padding(padding: const EdgeInsets.only(top: 6), child: Align(alignment: Alignment.centerLeft, child: child));

  Widget _header(BuildContext context, String text) {
    return Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 4),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary)),
      ),
    );
  }
}
