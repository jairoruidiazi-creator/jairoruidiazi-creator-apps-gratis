import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/settings.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';

/// Ajustes del adulto.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final Services s = AppScope.of(context);
    final AppSettings st = s.settings;
    return Scaffold(
      appBar: AppBar(title: const Text(S.ajustes)),
      body: ListenableBuilder(
        listenable: st,
        builder: (BuildContext context, Widget? _) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              SwitchListTile(
                value: st.voiceEnabled,
                onChanged: st.setVoiceEnabled,
                title: const Text(S.voz),
                subtitle: Text(s.voice.available ? 'Voz del sistema: ${s.voice.language ?? 'español'}' : 'Este dispositivo no tiene voz en español instalada; se muestra el texto.'),
              ),
              ListTile(
                title: const Text(S.velocidadVoz),
                subtitle: Slider(
                  value: st.voiceRate,
                  min: 0.3,
                  max: 0.7,
                  divisions: 8,
                  label: st.voiceRate <= 0.4 ? 'Lenta' : (st.voiceRate >= 0.6 ? 'Rápida' : 'Normal'),
                  onChanged: (double v) => st.setVoiceRate(v),
                  onChangeEnd: (double v) => s.voice.say('Así de rápido leo las instrucciones.'),
                ),
              ),
              SwitchListTile(value: st.sfxEnabled, onChanged: st.setSfxEnabled, title: const Text(S.sonidos)),
              const Divider(),
              ListTile(
                title: const Text(S.limiteSesion),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(st.sessionLimitMinutes == 0 ? S.sinLimite : S.minutos(st.sessionLimitMinutes)),
                    Slider(
                      value: st.sessionLimitMinutes.toDouble(),
                      min: 0,
                      max: 60,
                      divisions: 12,
                      label: st.sessionLimitMinutes == 0 ? S.sinLimite : S.minutos(st.sessionLimitMinutes),
                      onChanged: (double v) => st.setSessionLimitMinutes(v.round()),
                    ),
                    const Text(
                      'La OMS recomienda no más de una hora de pantalla al día entre los 2 y los 4 años. Al cumplirse el tiempo aparece la pantalla de descanso; un adulto puede dar 10 minutos más.',
                      style: TextStyle(color: PilasColors.tintaSuave, fontSize: 13),
                    ),
                  ],
                ),
              ),
              const Divider(),
              SwitchListTile(value: st.largeText, onChanged: st.setLargeText, title: const Text(S.textoGrande)),
              SwitchListTile(value: st.dyslexiaFont, onChanged: st.setDyslexiaFont, title: const Text(S.fuenteDislexia), subtitle: const Text('Usa la tipografía Andika en toda la app')),
              SwitchListTile(value: st.highContrast, onChanged: st.setHighContrast, title: const Text(S.altoContraste)),
            ],
          );
        },
      ),
    );
  }
}
