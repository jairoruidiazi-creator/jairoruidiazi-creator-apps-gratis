import 'package:flutter/material.dart';

import '../../core/app_info.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../legal/legal_document.dart';

/// Créditos y licencias de lo que la app usa.
class CreditsScreen extends StatelessWidget {
  const CreditsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(S.creditos)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          const Text('$kAppName $kAppVersion', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          const Text('Juegos didácticos gratuitos para niños de 3 a 11 años. Sin anuncios, sin suscripciones, sin cuenta y sin internet. Los datos de los niños se guardan en este dispositivo y no se envían a ningún servidor.'),
          const SizedBox(height: 18),
          const _Credit(titulo: 'Código', texto: 'Pilas es software libre con licencia Apache-2.0. El código está en el repositorio del proyecto apps-gratis en GitHub.'),
          const _Credit(titulo: 'Contenido propio', texto: 'Las láminas para colorear, los cuentos, las actividades y los textos son del proyecto y se publican con licencia CC BY 4.0.'),
          const _Credit(titulo: 'Pictogramas', texto: 'Twemoji, de Twitter y la comunidad que lo mantiene (jdecked/twemoji). Gráficos con licencia CC BY 4.0. https://creativecommons.org/licenses/by/4.0/'),
          const _Credit(titulo: 'Tipografías', texto: 'Lexend (Bonnie Shaver-Troup, Thomas Jockin y colaboradores) y Andika (SIL International), ambas con la SIL Open Font License 1.1.'),
          const _Credit(titulo: 'Sonidos', texto: 'Sintetizados por el proyecto; sin muestras de terceros.'),
          const _Credit(titulo: 'Referencias pedagógicas', texto: 'Derechos Básicos de Aprendizaje del Ministerio de Educación Nacional de Colombia, Common Core K-5 y las recomendaciones de tiempo de pantalla de la OMS (2019) y la AAP.'),
          const SizedBox(height: 12),
          const Text('Pilas no recopila ni envía datos. Si la familia comparte un dibujo o un informe, lo hace desde la hoja de compartir del sistema y bajo su control.', style: TextStyle(color: PilasColors.tintaSuave)),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const PrivacyPolicyScreen(spanish: true))),
                icon: const Icon(Icons.privacy_tip_outlined),
                label: const Text(S.politicaPrivacidad),
              ),
              OutlinedButton.icon(
                onPressed: () => showLicensePage(context: context, applicationName: kAppName, applicationVersion: kAppVersion),
                icon: const Icon(Icons.description_outlined),
                label: const Text(S.licenciasSoftware),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Credit extends StatelessWidget {
  const _Credit({required this.titulo, required this.texto});

  final String titulo;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(titulo, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(texto),
        ],
      ),
    );
  }
}
