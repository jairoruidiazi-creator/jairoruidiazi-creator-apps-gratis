import 'package:flutter/material.dart';

import '../../core/app_info.dart';
import '../../core/app_scope.dart';
import '../../core/settings.dart';
import '../legal/legal_document.dart';

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
    void save() {
      st.save();
      setState(() {});
    }

    return Scaffold(
      appBar: AppBar(title: Text(t(context, 'Ajustes', 'Settings'))),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: <Widget>[
          _header(context, t(context, 'General', 'General')),
          ListTile(
            title: Text(t(context, 'Idioma', 'Language')),
            subtitle: _left(SegmentedButton<String>(
              segments: const <ButtonSegment<String>>[ButtonSegment<String>(value: 'es', label: Text('Español')), ButtonSegment<String>(value: 'en', label: Text('English'))],
              selected: <String>{st.language},
              showSelectedIcon: false,
              onSelectionChanged: (Set<String> v) { st.language = v.first; save(); },
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
              onSelectionChanged: (Set<String> v) { st.themeMode = v.first; save(); },
            )),
          ),
          SwitchListTile(
            title: Text(t(context, 'Mantener la pantalla encendida', 'Keep the screen on')),
            subtitle: Text(t(context, 'En el afinador y el metrónomo.', 'In the tuner and the metronome.')),
            value: st.keepAwake,
            onChanged: (bool v) { st.keepAwake = v; save(); },
          ),
          _header(context, t(context, 'Metrónomo', 'Metronome')),
          SwitchListTile(
            title: Text(t(context, 'Vibrar en cada pulso', 'Vibrate on each beat')),
            value: st.haptics,
            onChanged: (bool v) { st.haptics = v; save(); },
          ),
          SwitchListTile(
            title: Text(t(context, 'Destello de pantalla', 'Screen flash')),
            value: st.flash,
            onChanged: (bool v) { st.flash = v; save(); },
          ),
          SwitchListTile(
            title: Text(t(context, 'Conteo hablado en el primer compás', 'Spoken count-in on the first bar')),
            subtitle: Text(t(context, 'Usa la voz del sistema; puede sonar un poco después del clic.', 'Uses the system voice; it may lag the click slightly.')),
            value: st.countInVoice,
            onChanged: (bool v) { st.countInVoice = v; save(); },
          ),
          ListTile(
            title: Text(t(context, 'Volumen del clic', 'Click volume')),
            subtitle: Slider(value: st.metronomeVolume, onChanged: (double v) { st.metronomeVolume = v; save(); }),
          ),
          ListTile(
            title: Text(t(context, 'Desfase visual', 'Visual offset')),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(t(context, 'Adelanta o atrasa la animación respecto al sonido (audífonos Bluetooth suelen necesitar +100 a +250 ms).', 'Shifts the animation relative to the sound (Bluetooth headphones usually need +100 to +250 ms).')),
                Slider(min: -200, max: 400, divisions: 60, value: st.visualOffsetMs.toDouble(), label: '${st.visualOffsetMs} ms', onChanged: (double v) { st.visualOffsetMs = v.round(); save(); }),
              ],
            ),
            trailing: Text('${st.visualOffsetMs} ms'),
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
                  onSelectionChanged: (Set<String> v) { st.recordingFormat = v.first; save(); },
                ),
              ],
            ),
          ),
          _header(context, t(context, 'Acerca de', 'About')),
          ListTile(
            title: const Text('$kAppName $kAppVersion'),
            subtitle: Text(t(context, 'Gratis, sin anuncios, sin cuenta y sin internet. Los datos quedan en tu dispositivo. Código Apache-2.0; audio con SoLoud (MIT).', 'Free, no ads, no account and no internet. Your data stays on your device. Code Apache-2.0; audio by SoLoud (MIT).')),
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
    );
  }

  Widget _left(Widget child) => Padding(padding: const EdgeInsets.only(top: 6), child: Align(alignment: Alignment.centerLeft, child: child));

  Widget _header(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 4),
      child: Text(text, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary)),
    );
  }
}
