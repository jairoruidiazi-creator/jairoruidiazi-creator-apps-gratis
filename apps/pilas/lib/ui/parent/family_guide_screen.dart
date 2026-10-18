import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../engine/mastery.dart';

/// Una sección de la guía: título y párrafos.
class GuideSection {
  const GuideSection(this.titulo, this.parrafos);

  final String titulo;
  final List<String> parrafos;
}

/// Guía para familias: cómo funciona Pilas, qué mide el informe, el tiempo de
/// juego, la accesibilidad y la privacidad. Las cifras salen de las mismas
/// constantes que usa la app (reglas de dominio y tiempos), y
/// test/grammar_test.dart revisa la redacción.
class FamilyGuideScreen extends StatelessWidget {
  const FamilyGuideScreen({super.key});

  static String _min(Duration d) => S.minutos(d.inMinutes);

  static final List<GuideSection> secciones = <GuideSection>[
    const GuideSection('Cómo empezar', <String>[
      'Un adulto crea un perfil para cada niño. Crear un perfil, entrar al panel de adultos y dar más tiempo pasan por la puerta para adultos: una multiplicación escrita en palabras.',
      'Cada niño entra tocando su perfil y ve los juegos de su edad, en cuatro tramos: de 3 a 4, de 5 a 6, de 7 a 8 y de 9 a 11 años. Si va más adelante o necesita algo más sencillo, el tramo se puede fijar en su perfil.',
    ]),
    const GuideSection('Para los que todavía no leen', <String>[
      'Los juegos de 3 a 6 años se siguen con la voz del sistema: cada instrucción se escucha y se repite tocando el altavoz.',
      'Si el teléfono o la tableta no tienen una voz en español, el inicio del niño lo avisa. Se instala en los ajustes de texto a voz del sistema.',
    ]),
    GuideSection('Niveles, pistas y pegatinas', <String>[
      'Si el niño se equivoca, arriba aparece una pista y puede intentarlo otra vez. Esa segunda oportunidad sirve para aprender, pero no cuenta como acierto. Si la pregunta tiene solo dos opciones no hay segunda oportunidad: se muestra la respuesta explicada.',
      'Para pasar de nivel hacen falta ${MasteryRule.eleccion.toAdvance} aciertos al primer intento en ${MasteryRule.eleccion.window} rondas. En los juegos de ordenar y en el trazo, ${MasteryRule.ordenar.toAdvance} rondas sin errores de ${MasteryRule.ordenar.window}. En memoria, laberintos, sudoku, rompecabezas, pixel art y colorear por números, ${MasteryRule.tablero.toAdvance} tableros resueltos con eficiencia de ${MasteryRule.tablero.window}. Cada nivel completado da una pegatina.',
      'Si le cuesta mucho, el juego baja un nivel sin anunciarlo, para que vuelva a tener éxito.',
    ]),
    const GuideSection('Qué dice el informe', <String>[
      'Una habilidad queda lograda cuando el niño domina el último nivel del juego que la evalúa en su tramo. El informe muestra las habilidades de su tramo actual: cuántas logró de las posibles en cada área.',
      'Los aciertos cuentan solo las respuestas al primer intento. Colorear, Dibujo y sellos y el modo libre del pixel art son juego libre: no tienen niveles ni habilidades y no suman aciertos.',
      'Cada juego tiene una ficha con lo que trabaja, una actividad para hacer en casa sin pantalla y una pregunta para conversar después.',
    ]),
    GuideSection('Tiempo de juego y descanso', <String>[
      'En Ajustes se elige el tiempo por sesión. Cada niño tiene su propio tiempo y solo cuenta mientras Pilas está abierta en pantalla. Si pasan ${_min(AppState.sessionGap)} sin jugar, la sesión termina y la siguiente empieza de cero.',
      'Al cumplirse el tiempo aparece un descanso de ${_min(AppState.restLength)}. No se salta cerrando la app ni con el botón de atrás, y para cambiar a otro jugador mientras alguien descansa hace falta un adulto. Un adulto puede dar ${_min(AppState.extraTime)} más.',
      'La OMS recomienda no más de una hora de pantalla al día entre los 2 y los 4 años, y que el tiempo con pantallas sea acompañado.',
    ]),
    const GuideSection('Accesibilidad', <String>[
      'Alto contraste: fondo blanco, texto negro y bordes marcados en toda la app; las figuras de colores llevan además una marca propia de cada color.',
      'Texto grande: agranda la letra sobre el tamaño elegido en el teléfono, con un tope para que todo siga cabiendo. Letra para los que empiezan a leer: usa en toda la app la tipografía Andika, de letras claras y fáciles de distinguir.',
      'Modo zurdo (en el perfil de cada niño): los botones y las herramientas de los juegos quedan a la izquierda, y en los trazos de pre-escritura las líneas acostadas empiezan por la derecha.',
    ]),
    const GuideSection('Privacidad', <String>[
      'Pilas no tiene anuncios, ni cuenta, ni compras, y no usa internet. Los perfiles, el avance y los dibujos quedan solo en este dispositivo y no se envían a ningún servidor. La voz del sistema solo recibe los textos de los juegos, nunca el nombre del niño.',
      'Compartir un dibujo, un informe o los datos del modo docente se hace con la hoja de compartir del sistema, siempre después de la puerta para adultos. Las copias que se preparan para compartir se borran al abrir la app otra vez. Para pasar los datos a otra tableta, exporta una copia en el modo docente e impórtala en la otra: se junta con lo que ya hay, sin borrar nada.',
    ]),
    const GuideSection('Cómo acompañar', <String>[
      'Jueguen juntos los primeros días y pregúntenle cómo supo la respuesta: explicar lo que pensó vale tanto como acertar.',
      'Usen las actividades de "En casa" de cada juego: lo que se aprende en la pantalla se afianza con las manos y con conversación.',
    ]),
  ];

  @override
  Widget build(BuildContext context) {
    final PilasPalette pal = PilasPalette.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text(S.guiaFamilias)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          for (final GuideSection sec in secciones) ...<Widget>[
            Semantics(header: true, child: Text(sec.titulo, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: pal.tinta))),
            const SizedBox(height: 6),
            for (final String p in sec.parrafos)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(p, style: TextStyle(fontSize: 16, height: 1.45, color: pal.tinta)),
              ),
            const SizedBox(height: 12),
          ],
          Text('Ayuda', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: pal.tinta)),
          const SizedBox(height: 6),
          Text('${S.soporteTexto} ${S.soporteUrl}', style: TextStyle(fontSize: 16, height: 1.45, color: pal.tinta)),
        ],
      ),
    );
  }
}
