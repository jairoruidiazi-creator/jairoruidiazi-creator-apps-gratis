import 'package:flutter/widgets.dart';

import '../games/carrera/carrera_generator.dart';
import '../games/choice/choice_game_screen.dart';
import '../games/clasifica/clasifica_generator.dart';
import '../games/colorear/colorear_screen.dart';
import '../games/emociones/emociones_generator.dart';
import '../games/intruso/intruso_generator.dart';
import '../games/laberinto/laberinto_screen.dart';
import '../games/memoria/memoria_screen.dart';
import '../games/oracion/oracion_generator.dart';
import '../games/palabra/palabra_round.dart';
import '../games/patrones/patrones_generator.dart';
import '../games/reloj/reloj_generator.dart';
import '../games/rutinas/rutinas_generator.dart';
import '../games/shell/order_game_screen.dart';
import '../games/sonidos/sonidos_generator.dart';
import '../games/sudoku/sudoku_screen.dart';
import '../games/tienda/tienda_screen.dart';
import '../model/age_band.dart';
import '../model/area.dart';
import 'game_def.dart';

/// Todos los juegos disponibles, en el orden en que se muestran.
class GameRegistry {
  GameRegistry._();

  static final List<GameDef> all = <GameDef>[
    GameDef(
      id: 'memoria',
      nombre: 'Parejas y memoria',
      area: Area.logica,
      emoji: '1f0cf',
      minBand: AgeBand.b3a4,
      maxBand: AgeBand.b9a11,
      skills: const <AgeBand, String>{
        AgeBand.b3a4: 'logica.3-4.emparejar',
        AgeBand.b5a6: 'logica.5-6.memoria',
        AgeBand.b7a8: 'logica.7-8.memoria',
        AgeBand.b9a11: 'logica.9-11.acertijos',
      },
      descripcion: 'Atención y memoria de trabajo: recordar dónde está cada carta y, en primaria, unir conceptos con ejemplos y operaciones con resultados.',
      enCasa: 'Jueguen a las parejas con cartas de verdad o con tapas de frascos pintadas.',
      pregunta: '¿Cómo hiciste para acordarte dónde estaba la carta?',
      build: (BuildContext context, GameLaunch launch) => MemoriaScreen(launch: launch),
    ),
    GameDef(
      id: 'patrones',
      nombre: '¿Qué sigue?',
      area: Area.logica,
      emoji: '1f501',
      minBand: AgeBand.b3a4,
      maxBand: AgeBand.b9a11,
      skills: const <AgeBand, String>{
        AgeBand.b3a4: 'logica.3-4.secuencias',
        AgeBand.b5a6: 'logica.5-6.patrones3',
        AgeBand.b7a8: 'logica.7-8.patrones',
        AgeBand.b9a11: 'logica.9-11.series',
      },
      descripcion: 'Patrones y series: continuar secuencias de colores, figuras y números, y nombrar la regla.',
      enCasa: 'Armen patrones con cubiertos, piedritas o botones: rojo, azul, rojo, azul, y pregunten qué sigue.',
      pregunta: '¿Cuál era la regla del patrón? Dímela con tus palabras.',
      build: (BuildContext context, GameLaunch launch) => ChoiceGameScreen(launch: launch, generator: PatronesGenerator()),
    ),
    GameDef(
      id: 'intruso',
      nombre: 'El intruso',
      area: Area.logica,
      emoji: '1f50e',
      minBand: AgeBand.b3a4,
      maxBand: AgeBand.b7a8,
      skills: const <AgeBand, String>{
        AgeBand.b3a4: 'logica.3-4.clasificar',
        AgeBand.b5a6: 'logica.5-6.quesobra',
        AgeBand.b7a8: 'logica.7-8.tablas',
      },
      descripcion: 'Clasificación y atributos: encontrar el elemento que no pertenece al grupo y decir el criterio.',
      enCasa: 'Pongan cuatro cosas de la cocina sobre la mesa, una que no sea de cocina, y pidan que explique cuál sobra y por qué.',
      pregunta: '¿Por qué ese era el intruso? ¿Qué tenían en común los demás?',
      build: (BuildContext context, GameLaunch launch) => ChoiceGameScreen(launch: launch, generator: IntrusoGenerator()),
    ),
    GameDef(
      id: 'laberintos',
      nombre: 'Laberintos',
      area: Area.logica,
      emoji: '1f9ed',
      minBand: AgeBand.b3a4,
      maxBand: AgeBand.b9a11,
      skills: const <AgeBand, String>{
        AgeBand.b3a4: 'logica.3-4.caminos',
        AgeBand.b5a6: 'logica.5-6.laberintos',
        AgeBand.b7a8: 'logica.7-8.planificar',
        AgeBand.b9a11: 'logica.9-11.estrategia',
      },
      descripcion: 'Planificación y orientación espacial: recorrer laberintos cada vez más grandes, y en primaria recoger una llave antes de la meta.',
      enCasa: 'Dibujen un laberinto en una hoja y pídanle que lo resuelva primero con el dedo y luego con el lápiz.',
      pregunta: '¿Miraste todo el camino antes de empezar o fuiste probando?',
      build: (BuildContext context, GameLaunch launch) => LaberintoScreen(launch: launch),
    ),
    GameDef(
      id: 'sudoku',
      nombre: 'Sudoku de figuras',
      area: Area.logica,
      emoji: '1f522',
      minBand: AgeBand.b5a6,
      maxBand: AgeBand.b9a11,
      skills: const <AgeBand, String>{
        AgeBand.b5a6: 'logica.5-6.sudoku4',
        AgeBand.b7a8: 'logica.7-8.sudoku',
        AgeBand.b9a11: 'logica.9-11.sudoku9',
      },
      descripcion: 'Razonamiento deductivo: sudokus de 4×4 con dibujos, de 6×6 y de 9×9 con números, siempre con solución única.',
      enCasa: 'Jueguen "qué falta": en una fila de cuatro cosas distintas, tapen una y pregunten cuál falta.',
      pregunta: '¿Cómo supiste qué iba en esa casilla? ¿Qué miraste primero?',
      build: (BuildContext context, GameLaunch launch) => SudokuScreen(launch: launch),
    ),
    GameDef(
      id: 'tienda',
      nombre: 'La tienda',
      area: Area.matematicas,
      emoji: '1f6d2',
      minBand: AgeBand.b3a4,
      maxBand: AgeBand.b9a11,
      skills: const <AgeBand, String>{
        AgeBand.b3a4: 'mate.3-4.contar10',
        AgeBand.b5a6: 'mate.5-6.dinero',
        AgeBand.b7a8: 'mate.7-8.dinero',
        AgeBand.b9a11: 'mate.9-11.dinero',
      },
      descripcion: 'Conteo, comparación, pagar con monedas y billetes colombianos, vueltas, multiplicación y presupuesto.',
      enCasa: 'En la tienda de verdad, dejen que el niño cuente las monedas o calcule las vueltas antes de que se las den.',
      pregunta: '¿Con qué monedas o billetes pagarías algo de tres mil quinientos pesos?',
      build: (BuildContext context, GameLaunch launch) => TiendaScreen(launch: launch),
    ),
    GameDef(
      id: 'carrera',
      nombre: 'Carrera de cálculo',
      area: Area.matematicas,
      emoji: '1f3c1',
      minBand: AgeBand.b5a6,
      maxBand: AgeBand.b9a11,
      skills: const <AgeBand, String>{
        AgeBand.b5a6: 'mate.5-6.sumas20',
        AgeBand.b7a8: 'mate.7-8.sumas100',
        AgeBand.b9a11: 'mate.9-11.operaciones',
      },
      descripcion: 'Cálculo mental con estrategia: sumas y restas, tablas, divisiones, decimales y fracciones. Sin reloj: la meta es la propia marca de aciertos.',
      enCasa: 'En el carro o en la fila del banco, lancen operaciones cortas: "¿cuánto es 7 más 8?". Si se equivoca, pídanle que lo cuente con los dedos o separando decenas.',
      pregunta: '¿Qué truco usaste para resolver la operación más difícil?',
      build: (BuildContext context, GameLaunch launch) => ChoiceGameScreen(launch: launch, generator: CarreraGenerator()),
    ),
    GameDef(
      id: 'reloj',
      nombre: 'El reloj',
      area: Area.matematicas,
      emoji: '23f0',
      minBand: AgeBand.b5a6,
      maxBand: AgeBand.b9a11,
      skills: const <AgeBand, String>{
        AgeBand.b5a6: 'mate.5-6.reloj',
        AgeBand.b7a8: 'mate.7-8.reloj',
        AgeBand.b9a11: 'mate.9-11.operaciones',
      },
      descripcion: 'Leer la hora en relojes de manecillas: en punto y media, cuartos, minutos de cinco en cinco y cuánto falta para la siguiente rutina.',
      enCasa: 'Pongan un reloj de manecillas en la cocina y pregunten la hora antes de las rutinas: "¿a qué hora nos vamos? Mira el reloj".',
      pregunta: '¿Qué hace la manecilla larga mientras la corta pasa de un número al siguiente?',
      build: (BuildContext context, GameLaunch launch) => ChoiceGameScreen(launch: launch, generator: RelojGenerator()),
    ),
    GameDef(
      id: 'sonidos',
      nombre: 'Sonidos y letras',
      area: Area.lenguaje,
      emoji: '1f524',
      minBand: AgeBand.b3a4,
      maxBand: AgeBand.b5a6,
      skills: const <AgeBand, String>{
        AgeBand.b3a4: 'lengua.3-4.vocales',
        AgeBand.b5a6: 'lengua.5-6.sonidos',
      },
      descripcion: 'Conciencia fonológica: reconocer el sonido con el que empieza una palabra y contar sílabas.',
      enCasa: 'Jueguen a "veo veo" con sonidos: "veo algo que empieza con mmm".',
      pregunta: '¿Con qué sonido empieza tu nombre? ¿Y el de tu mejor amigo?',
      build: (BuildContext context, GameLaunch launch) => ChoiceGameScreen(launch: launch, generator: SonidosGenerator()),
    ),
    GameDef(
      id: 'palabra',
      nombre: 'Arma la palabra',
      area: Area.lenguaje,
      emoji: '1f9e9',
      minBand: AgeBand.b5a6,
      maxBand: AgeBand.b9a11,
      skills: const <AgeBand, String>{
        AgeBand.b5a6: 'lengua.5-6.alfabeto',
        AgeBand.b7a8: 'lengua.7-8.ortografia',
        AgeBand.b9a11: 'lengua.9-11.tildes',
      },
      descripcion: 'Escritura: ordenar las letras de una palabra; en primaria con letras que se confunden (b/v, ll/y, h) y con tildes.',
      enCasa: 'Escriban en papelitos las letras del nombre del niño y pídanle que lo arme; después, el nombre de su mascota o de un amigo.',
      pregunta: '¿Qué palabra te costó más armar? Dila despacio por sílabas.',
      build: (BuildContext context, GameLaunch launch) => OrderGameScreen(launch: launch, builder: palabraRound),
    ),
    GameDef(
      id: 'oracion',
      nombre: 'Ordena la oración',
      area: Area.lenguaje,
      emoji: '1f4ac',
      minBand: AgeBand.b5a6,
      maxBand: AgeBand.b9a11,
      skills: const <AgeBand, String>{
        AgeBand.b5a6: 'lengua.5-6.lectura',
        AgeBand.b7a8: 'lengua.7-8.oraciones',
        AgeBand.b9a11: 'lengua.9-11.sintaxis',
      },
      descripcion: 'Sintaxis y lectura: ordenar palabras para formar oraciones con sentido, de tres palabras a oraciones con conectores.',
      enCasa: 'Digan una oración desordenada en voz alta ("duerme el gato") y pídanle que la arregle.',
      pregunta: '¿Cómo supiste cuál palabra iba primero?',
      build: (BuildContext context, GameLaunch launch) => OrderGameScreen(launch: launch, builder: oracionRound),
    ),
    GameDef(
      id: 'clasifica',
      nombre: 'Clasifica seres vivos',
      area: Area.ciencias,
      emoji: '1f43e',
      minBand: AgeBand.b3a4,
      maxBand: AgeBand.b9a11,
      skills: const <AgeBand, String>{
        AgeBand.b3a4: 'ciencias.3-4.animales',
        AgeBand.b5a6: 'ciencias.5-6.seresvivos',
        AgeBand.b7a8: 'ciencias.7-8.ciclos',
        AgeBand.b9a11: 'ciencias.9-11.ecosistemas',
      },
      descripcion: 'Hábitats, grupos de animales y cómo se mueven, con fauna de Colombia y América Latina.',
      enCasa: 'Cuando vean un animal, pregunten: ¿dónde vive?, ¿qué come?, ¿tiene pelo, plumas o escamas?',
      pregunta: '¿Qué diferencia hay entre un ave y un mamífero?',
      build: (BuildContext context, GameLaunch launch) => ChoiceGameScreen(launch: launch, generator: ClasificaGenerator()),
    ),
    GameDef(
      id: 'colorear',
      nombre: 'Colorear',
      area: Area.creatividad,
      emoji: '1f58d',
      minBand: AgeBand.b3a4,
      maxBand: AgeBand.b9a11,
      skills: const <AgeBand, String>{
        AgeBand.b3a4: 'arte.3-4.colorear',
        AgeBand.b5a6: 'arte.5-6.colorearnumeros',
        AgeBand.b7a8: 'arte.7-8.pasoapaso',
        AgeBand.b9a11: 'arte.9-11.simetria',
      },
      descripcion: 'Motricidad fina y atención: pintar láminas con la paleta, sin bien ni mal.',
      enCasa: 'Tengan a mano hojas y crayones: colorear en papel entrena la mano igual que en la pantalla.',
      pregunta: '¿Qué colores elegiste y por qué?',
      roundBased: false,
      build: (BuildContext context, GameLaunch launch) => ColorearScreen(launch: launch),
    ),
    GameDef(
      id: 'colorear_numeros',
      nombre: 'Colorear por números',
      area: Area.creatividad,
      emoji: '1f3a8',
      minBand: AgeBand.b5a6,
      maxBand: AgeBand.b9a11,
      skills: const <AgeBand, String>{
        AgeBand.b5a6: 'arte.5-6.colorearnumeros',
        AgeBand.b7a8: 'arte.7-8.pixel',
        AgeBand.b9a11: 'arte.9-11.simetria',
      },
      descripcion: 'Relacionar cada zona con su número (o su letra en primaria) y terminar la lámina completa.',
      enCasa: 'Hagan juntos una lámina por números en papel: numeren las zonas y asignen un color a cada número.',
      pregunta: '¿Qué número tenía el color que más usaste?',
      roundBased: false,
      build: (BuildContext context, GameLaunch launch) => ColorearScreen(launch: launch, porNumeros: true),
    ),
    GameDef(
      id: 'emociones',
      nombre: '¿Qué siento?',
      area: Area.socioemocional,
      emoji: '1f642',
      minBand: AgeBand.b3a4,
      maxBand: AgeBand.b7a8,
      skills: const <AgeBand, String>{
        AgeBand.b3a4: 'socio.3-4.emociones',
        AgeBand.b5a6: 'socio.5-6.regulacion',
        AgeBand.b7a8: 'socio.7-8.conflictos',
      },
      descripcion: 'Reconocer emociones en caras y situaciones, y elegir una forma sana de calmarse.',
      enCasa: 'Al final del día pregunten "¿cómo te sentiste hoy?" y cuenten también cómo se sintieron ustedes.',
      pregunta: '¿Qué haces tú cuando estás enojado y quieres calmarte?',
      build: (BuildContext context, GameLaunch launch) => ChoiceGameScreen(launch: launch, generator: EmocionesGenerator()),
    ),
    GameDef(
      id: 'rutinas',
      nombre: 'Tablero de rutinas',
      area: Area.socioemocional,
      emoji: '1f4c5',
      minBand: AgeBand.b3a4,
      maxBand: AgeBand.b5a6,
      skills: const <AgeBand, String>{
        AgeBand.b3a4: 'socio.3-4.rutinas',
        AgeBand.b5a6: 'socio.5-6.turnos',
      },
      descripcion: 'Secuencias de la vida diaria: ordenar los pasos de levantarse, lavarse los dientes, sembrar una planta o curar un raspón.',
      enCasa: 'Hagan juntos un cartel con fotos o dibujos de la rutina de la mañana y péguenlo donde el niño lo vea.',
      pregunta: '¿Qué haces tú primero cuando te levantas? ¿Y después?',
      build: (BuildContext context, GameLaunch launch) => OrderGameScreen(launch: launch, builder: rutinaRound),
    ),
  ];

  static GameDef? byId(String id) {
    for (final GameDef g in all) {
      if (g.id == id) {
        return g;
      }
    }
    return null;
  }

  static List<GameDef> forBand(AgeBand band) => all.where((GameDef g) => g.supports(band)).toList();

  static List<GameDef> forAreaAndBand(Area area, AgeBand band) => all.where((GameDef g) => g.area == area && g.supports(band)).toList();
}
