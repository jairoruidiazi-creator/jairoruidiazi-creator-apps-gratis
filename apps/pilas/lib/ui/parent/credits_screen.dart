import 'package:flutter/material.dart';

import '../../core/strings.dart';
import '../../core/theme.dart';

/// Créditos y licencias de lo que la app usa.
class CreditsScreen extends StatelessWidget {
  const CreditsScreen({super.key});

  static const String version = '0.1.0';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(S.creditos)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: const <Widget>[
          Text('Pilas $version', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          SizedBox(height: 6),
          Text('Juegos didácticos gratuitos para niños de 3 a 11 años. Sin anuncios, sin suscripciones, sin cuenta y sin internet. Los datos de los niños quedan solo en este dispositivo.'),
          SizedBox(height: 18),
          _Credit(titulo: 'Código', texto: 'Pilas es software libre con licencia Apache-2.0. El código está en el repositorio del proyecto apps-gratis en GitHub.'),
          _Credit(titulo: 'Contenido propio', texto: 'Las láminas para colorear, los cuentos, las actividades y los textos son del proyecto y se publican con licencia CC BY 4.0.'),
          _Credit(titulo: 'Pictogramas', texto: 'Twemoji, de Twitter y la comunidad que lo mantiene (jdecked/twemoji). Gráficos con licencia CC BY 4.0. https://creativecommons.org/licenses/by/4.0/'),
          _Credit(titulo: 'Tipografías', texto: 'Lexend (Bonnie Shaver-Troup, Thomas Jockin y colaboradores) y Andika (SIL International), ambas con la SIL Open Font License 1.1.'),
          _Credit(titulo: 'Sonidos', texto: 'Sintetizados por el proyecto; sin muestras de terceros.'),
          _Credit(titulo: 'Referencias pedagógicas', texto: 'Derechos Básicos de Aprendizaje del Ministerio de Educación Nacional de Colombia, Common Core K-5 y las recomendaciones de tiempo de pantalla de la OMS (2019) y la AAP.'),
          SizedBox(height: 12),
          Text('Pilas no recopila ni envía datos. Si la familia comparte un dibujo o un informe, lo hace desde la hoja de compartir del sistema y bajo su control.', style: TextStyle(color: PilasColors.tintaSuave)),
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
