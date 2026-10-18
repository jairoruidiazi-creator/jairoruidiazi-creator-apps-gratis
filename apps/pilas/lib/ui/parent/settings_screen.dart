import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/settings.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';

/// Ajustes del adulto. Cada opción dice qué hace de verdad.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final Services s = AppScope.of(context);
    final AppSettings st = s.settings;
    return Scaffold(
      appBar: AppBar(title: const Text(S.ajustes)),
      body: ListenableBuilder(
        listenable: Listenable.merge(<Listenable>[st, s.voice]),
        builder: (BuildContext context, Widget? _) {
          final PilasPalette pal = PilasPalette.of(context);
          final String vozTexto = !s.voice.ready
              ? 'Preparando la voz del sistema…'
              : (s.voice.available ? 'Voz del sistema: ${s.voice.language ?? 'español'}.' : '${S.sinVozTitulo}. ${S.sinVozTexto}');
          return ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              SwitchListTile(
                key: const ValueKey<String>('ajuste-voz'),
                value: st.voiceEnabled,
                onChanged: st.setVoiceEnabled,
                title: const Text(S.voz),
                subtitle: Text(vozTexto),
              ),
              ListTile(
                title: const Text(S.velocidadVoz),
                subtitle: Slider(
                  value: st.voiceRate,
                  min: 0.3,
                  max: 0.7,
                  divisions: 8,
                  label: st.voiceRate <= 0.4 ? 'Lenta' : (st.voiceRate >= 0.6 ? 'Rápida' : 'Normal'),
                  semanticFormatterCallback: (double v) => v <= 0.4 ? 'Lenta' : (v >= 0.6 ? 'Rápida' : 'Normal'),
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
                    Text(st.sessionLimitMinutes == 0 ? S.sinLimite : S.minutos(st.sessionLimitMinutes), style: TextStyle(fontWeight: FontWeight.w700, color: pal.tinta)),
                    Slider(
                      key: const ValueKey<String>('ajuste-limite'),
                      value: st.sessionLimitMinutes.toDouble().clamp(0, 60).toDouble(),
                      min: 0,
                      max: 60,
                      divisions: 12,
                      label: st.sessionLimitMinutes == 0 ? S.sinLimite : S.minutos(st.sessionLimitMinutes),
                      semanticFormatterCallback: (double v) => v == 0 ? S.sinLimite : S.minutos(v.round()),
                      onChanged: (double v) => st.setSessionLimitMinutes(v.round()),
                    ),
                    Text(S.limiteDetalle, style: TextStyle(color: pal.tintaSuave, fontSize: 13)),
                  ],
                ),
              ),
              const Divider(),
              SwitchListTile(value: st.largeText, onChanged: st.setLargeText, title: const Text(S.textoGrande), subtitle: const Text(S.textoGrandeDetalle)),
              SwitchListTile(value: st.dyslexiaFont, onChanged: st.setDyslexiaFont, title: const Text(S.letraLectores), subtitle: const Text(S.letraLectoresDetalle)),
              SwitchListTile(value: st.highContrast, onChanged: st.setHighContrast, title: const Text(S.altoContraste), subtitle: const Text(S.altoContrasteDetalle)),
              const SizedBox(height: 8),
              Text('El modo zurdo se elige en el perfil de cada niño.', style: TextStyle(color: pal.tintaSuave, fontSize: 13)),
            ],
          );
        },
      ),
    );
  }
}
