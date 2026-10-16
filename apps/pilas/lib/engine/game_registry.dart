import 'package:flutter/widgets.dart';

import '../games/banco/bank_generator.dart';
import '../games/banco/cuerpo_bank.dart';
import '../games/banco/decisiones_bank.dart';
import '../games/banco/laboratorio_bank.dart';
import '../games/carrera/carrera_generator.dart';
import '../games/choice/choice_game_screen.dart';
import '../games/clasifica/clasifica_generator.dart';
import '../games/cocina/cocina_generator.dart';
import '../games/colorear/colorear_screen.dart';
import '../games/cuentos/cuentos_screen.dart';
import '../games/dibujo/dibujo_screen.dart';
import '../games/emociones/emociones_generator.dart';
import '../games/figuras/figuras_generator.dart';
import '../games/intruso/intruso_generator.dart';
import '../games/laberinto/laberinto_screen.dart';
import '../games/memoria/memoria_screen.dart';
import '../games/oracion/oracion_generator.dart';
import '../games/palabra/palabra_round.dart';
import '../games/patrones/patrones_generator.dart';
import '../games/pixel/pixel_screen.dart';
import '../games/reloj/reloj_generator.dart';
import '../games/rompecabezas/rompecabezas_screen.dart';
import '../games/rutinas/rutinas_generator.dart';
import '../games/shell/order_game_screen.dart';
import '../games/sonidos/sonidos_generator.dart';
import '../games/sudoku/sudoku_screen.dart';
import '../games/tienda/tienda_screen.dart';
import '../games/trazo/trazo_screen.dart';
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
      id: 'rompecabezas',
      nombre: 'Tangram y rompecabezas',
      area: Area.logica,
      emoji: '1f9e9',
      minBand: AgeBand.b3a4,
      maxBand: AgeBand.b9a11,
      skills: const <AgeBand, String>{
        AgeBand.b3a4: 'logica.3-4.encajar',
        AgeBand.b5a6: 'logica.5-6.tangram',
        AgeBand.b7a8: 'logica.7-8.planificar',
        AgeBand.b9a11: 'logica.9-11.bloques',
      },
      descripcion: 'Percepción espacial: encajar figuras en su silueta (por forma y tamaño) y armar imágenes intercambiando fichas.',
      enCasa: 'Recorten una foto o un dibujo en seis pedazos y pídanle que lo arme; después, en nueve.',
      pregunta: '¿Cómo sabías dónde iba cada pedazo? ¿Qué miraste: los bordes, los colores?',
      build: (BuildContext context, GameLaunch launch) => RompecabezasScreen(launch: launch),
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
      id: 'cocina',
      nombre: 'Cocina de medidas',
      area: Area.matematicas,
      emoji: '1f373',
      minBand: AgeBand.b5a6,
      maxBand: AgeBand.b9a11,
      skills: const <AgeBand, String>{
        AgeBand.b5a6: 'mate.5-6.medidas',
        AgeBand.b7a8: 'mate.7-8.fracciones',
        AgeBand.b9a11: 'mate.9-11.fracciones',
      },
      descripcion: 'Medidas y fracciones con cosas de cocina: lleno y vacío, tazas, balanza, porciones de pizza, fracciones equivalentes y recetas.',
      enCasa: 'Cocinen juntos: que mida las tazas, parta la arepa en cuatro y diga qué fracción se comió.',
      pregunta: 'Si partes una pizza en 8 y te comes 2 pedazos, ¿qué fracción comiste? ¿Y cuánta queda?',
      build: (BuildContext context, GameLaunch launch) => ChoiceGameScreen(launch: launch, generator: CocinaGenerator()),
    ),
    GameDef(
      id: 'figuras',
      nombre: 'Constructor de figuras',
      area: Area.matematicas,
      emoji: '1f4d0',
      minBand: AgeBand.b3a4,
      maxBand: AgeBand.b9a11,
      skills: const <AgeBand, String>{
        AgeBand.b3a4: 'mate.3-4.formas',
        AgeBand.b5a6: 'mate.5-6.medidas',
        AgeBand.b7a8: 'mate.7-8.perimetro',
        AgeBand.b9a11: 'mate.9-11.area',
      },
      descripcion: 'Geometría: reconocer formas y objetos con esa forma, contar lados, comparar longitudes, perímetro y área sobre cuadrícula.',
      enCasa: 'Busquen formas en la casa: ¿qué cosas son círculos?, ¿cuáles rectángulos? Midan con pasos el borde de una habitación.',
      pregunta: '¿Cuál es la diferencia entre el perímetro y el área de la cancha?',
      build: (BuildContext context, GameLaunch launch) => ChoiceGameScreen(launch: launch, generator: FigurasGenerator()),
    ),
    GameDef(
      id: 'trazo',
      nombre: 'Trazo de letras',
      area: Area.lenguaje,
      emoji: '270f',
      minBand: AgeBand.b3a4,
      maxBand: AgeBand.b5a6,
      skills: const <AgeBand, String>{
        AgeBand.b3a4: 'lengua.3-4.trazos',
        AgeBand.b5a6: 'lengua.5-6.trazo',
      },
      descripcion: 'Grafomotricidad: trazos de pre-escritura, vocales, letras mayúsculas y minúsculas y números, siguiendo la guía con el dedo.',
      enCasa: 'Tracen letras grandes en una bandeja con harina o arena, y después en papel con crayón grueso.',
      pregunta: '¿Por dónde empieza la letra? Muéstrame con el dedo en el aire.',
      build: (BuildContext context, GameLaunch launch) => TrazoScreen(launch: launch),
    ),
    GameDef(
      id: 'cuentos',
      nombre: 'Cuentos con voz',
      area: Area.lenguaje,
      emoji: '1f4d6',
      minBand: AgeBand.b3a4,
      maxBand: AgeBand.b9a11,
      skills: const <AgeBand, String>{
        AgeBand.b3a4: 'lengua.3-4.cuentos',
        AgeBand.b5a6: 'lengua.5-6.lectura',
        AgeBand.b7a8: 'lengua.7-8.comprension',
        AgeBand.b9a11: 'lengua.9-11.textos',
      },
      descripcion: 'Comprensión lectora y escucha: cuentos originales leídos en voz alta, con tres preguntas que van de lo literal a la inferencia.',
      enCasa: 'Después de leer un cuento, pregunten "¿qué pasó primero?", "¿por qué crees que hizo eso?" y "¿qué habrías hecho tú?".',
      pregunta: '¿Qué parte del cuento te gustó más y por qué?',
      build: (BuildContext context, GameLaunch launch) => CuentosScreen(launch: launch),
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
      id: 'cuerpo',
      nombre: 'Arma el cuerpo',
      area: Area.ciencias,
      emoji: '1fac0',
      minBand: AgeBand.b3a4,
      maxBand: AgeBand.b9a11,
      skills: const <AgeBand, String>{
        AgeBand.b3a4: 'ciencias.3-4.cuerpo',
        AgeBand.b5a6: 'ciencias.5-6.sentidos',
        AgeBand.b7a8: 'ciencias.7-8.organos',
        AgeBand.b9a11: 'ciencias.9-11.cuerpo',
      },
      descripcion: 'El cuerpo humano: partes y para qué sirven, los cinco sentidos, órganos y sistemas, y hábitos que lo cuidan.',
      enCasa: 'Jueguen "Simón dice" con partes del cuerpo, y de noche sientan juntos cómo late el corazón después de saltar.',
      pregunta: '¿Qué pasa en tu cuerpo cuando corres mucho? ¿Por qué?',
      build: (BuildContext context, GameLaunch launch) => ChoiceGameScreen(launch: launch, generator: BankGenerator(CuerpoBank.all)),
    ),
    GameDef(
      id: 'laboratorio',
      nombre: 'Laboratorio guiado',
      area: Area.ciencias,
      emoji: '1f9ea',
      minBand: AgeBand.b3a4,
      maxBand: AgeBand.b9a11,
      skills: const <AgeBand, String>{
        AgeBand.b3a4: 'ciencias.3-4.diaynoche',
        AgeBand.b5a6: 'ciencias.5-6.experimentos',
        AgeBand.b7a8: 'ciencias.7-8.materia',
        AgeBand.b9a11: 'ciencias.9-11.metodo',
      },
      descripcion: 'Predecir y explicar: día y noche, flota o se hunde, imanes, estados de la materia, mezclas y el método científico.',
      enCasa: 'Hagan el experimento de verdad: una tina con agua y cinco objetos; que adivine antes cuál flota y por qué.',
      pregunta: '¿Qué crees que va a pasar y por qué? Después lo probamos.',
      build: (BuildContext context, GameLaunch launch) => ChoiceGameScreen(launch: launch, generator: BankGenerator(LaboratorioBank.all)),
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
      id: 'dibujo',
      nombre: 'Dibujo y sellos',
      area: Area.creatividad,
      emoji: '1f58c',
      minBand: AgeBand.b3a4,
      maxBand: AgeBand.b9a11,
      skills: const <AgeBand, String>{
        AgeBand.b3a4: 'arte.3-4.pintar',
        AgeBand.b5a6: 'arte.5-6.dibujarformas',
        AgeBand.b7a8: 'arte.7-8.pasoapaso',
        AgeBand.b9a11: 'arte.9-11.diseno',
      },
      descripcion: 'Expresión libre: pincel de tres grosores, borrador, sellos de pictogramas y guardado en Mis dibujos.',
      enCasa: 'Pregúntenle qué dibujó y escriban juntos el título debajo del dibujo.',
      pregunta: '¿Qué historia cuenta tu dibujo?',
      roundBased: false,
      build: (BuildContext context, GameLaunch launch) => DibujoScreen(launch: launch),
    ),
    GameDef(
      id: 'pixel',
      nombre: 'Pixel art',
      area: Area.creatividad,
      emoji: '1f7e6',
      minBand: AgeBand.b7a8,
      maxBand: AgeBand.b9a11,
      skills: const <AgeBand, String>{
        AgeBand.b7a8: 'arte.7-8.pixel',
        AgeBand.b9a11: 'arte.9-11.simetria',
      },
      descripcion: 'Cuadrícula de colores en tres modos: libre, copiar un modelo (filas y columnas) y completar la mitad en espejo (simetría).',
      enCasa: 'En papel cuadriculado, dibujen la mitad de una figura y que el niño complete la otra mitad.',
      pregunta: '¿Cómo supiste qué casilla pintar en el espejo?',
      build: (BuildContext context, GameLaunch launch) => PixelScreen(launch: launch),
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
    GameDef(
      id: 'decisiones',
      nombre: 'Historias con decisiones',
      area: Area.socioemocional,
      emoji: '1f9ed',
      minBand: AgeBand.b5a6,
      maxBand: AgeBand.b9a11,
      skills: const <AgeBand, String>{
        AgeBand.b5a6: 'socio.5-6.turnos',
        AgeBand.b7a8: 'socio.7-8.seguridad',
        AgeBand.b9a11: 'socio.9-11.pantallas',
      },
      descripcion: 'Situaciones cotidianas con tres salidas: turnos y acuerdos, seguridad en casa, calle e internet, trabajo en equipo y pantallas.',
      enCasa: 'Repasen juntos quiénes son los adultos de confianza del niño y qué hacer si alguien le pide guardar un secreto incómodo.',
      pregunta: '¿A quién le contarías si algo en internet te hiciera sentir mal?',
      build: (BuildContext context, GameLaunch launch) => ChoiceGameScreen(launch: launch, generator: BankGenerator(DecisionesBank.all)),
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
