import 'age_band.dart';
import 'area.dart';

/// Una habilidad del mapa por edad. Cada juego evalúa como mucho una
/// habilidad por tramo, y cada habilidad de un tramo la evalúa al menos un
/// juego de ese tramo (test/skills_coverage_test.dart lo comprueba): el
/// informe nunca muestra una habilidad que no se pueda lograr.
class Skill {
  const Skill({
    required this.id,
    required this.area,
    required this.band,
    required this.nombre,
    required this.descripcion,
  });

  final String id;
  final Area area;
  final AgeBand band;

  /// Nombre corto que ve el adulto en el informe.
  final String nombre;

  /// Qué sabe hacer el niño cuando la logra (lo que el juego de verdad mide).
  final String descripcion;
}

/// Catálogo completo del mapa de habilidades. Una habilidad se logra al
/// dominar el último nivel del juego que la evalúa en el tramo del niño,
/// contando solo las respuestas acertadas al primer intento.
class SkillCatalog {
  SkillCatalog._();

  static const List<Skill> all = <Skill>[
    // Razonamiento y lógica
    Skill(id: 'logica.3-4.emparejar', area: Area.logica, band: AgeBand.b3a4, nombre: 'Emparejar y recordar', descripcion: 'Encuentra parejas iguales entre cuatro y ocho cartas recordando dónde estaban.'),
    Skill(id: 'logica.3-4.secuencias', area: Area.logica, band: AgeBand.b3a4, nombre: 'Secuencias', descripcion: 'Continúa patrones de colores y figuras como rojo, azul, rojo, azul.'),
    Skill(id: 'logica.3-4.clasificar', area: Area.logica, band: AgeBand.b3a4, nombre: 'Clasificar', descripcion: 'Encuentra el que no va con los demás por su color, su forma o el tipo de cosa que es.'),
    Skill(id: 'logica.3-4.caminos', area: Area.logica, band: AgeBand.b3a4, nombre: 'Seguir un camino', descripcion: 'Lleva a un personaje por un laberinto pequeño hasta la meta.'),
    Skill(id: 'logica.3-4.encajar', area: Area.logica, band: AgeBand.b3a4, nombre: 'Encajar formas', descripcion: 'Coloca cada figura en su silueta.'),
    Skill(id: 'logica.5-6.memoria', area: Area.logica, band: AgeBand.b5a6, nombre: 'Memoria de trabajo', descripcion: 'Recuerda la posición de hasta doce cartas para formar parejas.'),
    Skill(id: 'logica.5-6.patrones', area: Area.logica, band: AgeBand.b5a6, nombre: 'Patrones de tres y cuatro', descripcion: 'Continúa patrones de tres y cuatro elementos y series que cuentan de 1 en 1, de 2 en 2 y de 10 en 10.'),
    Skill(id: 'logica.5-6.quesobra', area: Area.logica, band: AgeBand.b5a6, nombre: 'Qué sobra', descripcion: 'Encuentra el que no pertenece al grupo: por dónde vive, cómo se mueve o para qué sirve.'),
    Skill(id: 'logica.5-6.laberintos', area: Area.logica, band: AgeBand.b5a6, nombre: 'Laberintos', descripcion: 'Planea un camino con desvíos y callejones sin salida.'),
    Skill(id: 'logica.5-6.encajar', area: Area.logica, band: AgeBand.b5a6, nombre: 'Formas y tamaños', descripcion: 'Encaja figuras en su silueta fijándose en la forma y en el tamaño.'),
    Skill(id: 'logica.5-6.sudoku4', area: Area.logica, band: AgeBand.b5a6, nombre: 'Sudoku de 4 por 4', descripcion: 'Completa cuadrículas de 4 por 4 donde nada se repite en una fila, una columna ni una región.'),
    Skill(id: 'logica.7-8.memoria', area: Area.logica, band: AgeBand.b7a8, nombre: 'Memoria con conceptos', descripcion: 'Une cada grupo con su ejemplo y cada operación con su resultado recordando dónde está cada carta.'),
    Skill(id: 'logica.7-8.patrones', area: Area.logica, band: AgeBand.b7a8, nombre: 'Patrones numéricos', descripcion: 'Descubre la regla de una serie de números: sumar, restar, duplicar o seguir una tabla.'),
    Skill(id: 'logica.7-8.criterios', area: Area.logica, band: AgeBand.b7a8, nombre: 'Clasificar con criterios', descripcion: 'Encuentra el intruso por grupo de animal, familia de instrumento, medio de transporte o propiedad de los números.'),
    Skill(id: 'logica.7-8.planificar', area: Area.logica, band: AgeBand.b7a8, nombre: 'Planificar la ruta', descripcion: 'Recorre laberintos grandes, algunos con una llave que hay que recoger antes de la meta.'),
    Skill(id: 'logica.7-8.rompecabezas', area: Area.logica, band: AgeBand.b7a8, nombre: 'Armar imágenes', descripcion: 'Arma imágenes de 9 y de 16 fichas intercambiándolas con pocos movimientos.'),
    Skill(id: 'logica.7-8.sudoku', area: Area.logica, band: AgeBand.b7a8, nombre: 'Sudoku de 6 por 6', descripcion: 'Deduce los números que faltan en cuadrículas de 6 por 6.'),
    Skill(id: 'logica.9-11.memoria', area: Area.logica, band: AgeBand.b9a11, nombre: 'Memoria con operaciones', descripcion: 'Une multiplicaciones, divisiones y dobles con su resultado entre hasta veinte cartas.'),
    Skill(id: 'logica.9-11.series', area: Area.logica, band: AgeBand.b9a11, nombre: 'Series con dos reglas', descripcion: 'Continúa series con pasos que crecen, cuadrados, alternancias y multiplicaciones.'),
    Skill(id: 'logica.9-11.estrategia', area: Area.logica, band: AgeBand.b9a11, nombre: 'Estrategia en laberintos', descripcion: 'Planea la ruta completa en laberintos grandes con llave, sin dar vueltas de más.'),
    Skill(id: 'logica.9-11.rompecabezas', area: Area.logica, band: AgeBand.b9a11, nombre: 'Rompecabezas grandes', descripcion: 'Arma imágenes de 9 a 25 fichas con pocos movimientos.'),
    Skill(id: 'logica.9-11.sudoku9', area: Area.logica, band: AgeBand.b9a11, nombre: 'Sudoku de 9 por 9', descripcion: 'Resuelve sudokus de 6 por 6 y de 9 por 9.'),

    // Matemáticas
    Skill(id: 'mate.3-4.contar10', area: Area.matematicas, band: AgeBand.b3a4, nombre: 'Contar y comparar', descripcion: 'Cuenta hasta diez, paga con monedas iguales y dice dónde hay más y dónde hay menos.'),
    Skill(id: 'mate.3-4.formas', area: Area.matematicas, band: AgeBand.b3a4, nombre: 'Formas básicas', descripcion: 'Reconoce el círculo, el cuadrado, el triángulo y otras formas, y cuenta sus lados.'),
    Skill(id: 'mate.5-6.dinero', area: Area.matematicas, band: AgeBand.b5a6, nombre: 'Monedas y precios', descripcion: 'Paga precios exactos con monedas y billetes de hasta 2.000 pesos y suma dos precios.'),
    Skill(id: 'mate.5-6.sumas20', area: Area.matematicas, band: AgeBand.b5a6, nombre: 'Sumas y restas hasta 20', descripcion: 'Suma y resta hasta 20 contando hacia adelante y hacia atrás.'),
    Skill(id: 'mate.5-6.reloj', area: Area.matematicas, band: AgeBand.b5a6, nombre: 'Reloj en punto y media', descripcion: 'Lee las horas en punto y las medias en un reloj de manecillas.'),
    Skill(id: 'mate.5-6.medidas', area: Area.matematicas, band: AgeBand.b5a6, nombre: 'Medidas comparadas', descripcion: 'Compara cuánto hay en un vaso, cuenta tazas y lee una balanza.'),
    Skill(id: 'mate.5-6.figuras', area: Area.matematicas, band: AgeBand.b5a6, nombre: 'Lados y longitudes', descripcion: 'Cuenta lados, compara longitudes y cuenta los cuadritos de una figura.'),
    Skill(id: 'mate.7-8.dinero', area: Area.matematicas, band: AgeBand.b7a8, nombre: 'Dinero en pesos', descripcion: 'Paga con billetes, calcula las vueltas y multiplica precios.'),
    Skill(id: 'mate.7-8.calculo', area: Area.matematicas, band: AgeBand.b7a8, nombre: 'Cálculo hasta 100 y tablas', descripcion: 'Suma y resta hasta 100 con llevadas, usa las tablas de multiplicar y divide sin resto.'),
    Skill(id: 'mate.7-8.reloj', area: Area.matematicas, band: AgeBand.b7a8, nombre: 'Reloj con minutos', descripcion: 'Lee cuartos y minutos de cinco en cinco y calcula cuánto falta.'),
    Skill(id: 'mate.7-8.fracciones', area: Area.matematicas, band: AgeBand.b7a8, nombre: 'Fracciones simples', descripcion: 'Reconoce medios, tercios y cuartos, compara fracciones y ajusta una receta.'),
    Skill(id: 'mate.7-8.perimetro', area: Area.matematicas, band: AgeBand.b7a8, nombre: 'Perímetro', descripcion: 'Calcula el perímetro contando lados en una cuadrícula, con medidas y en figuras en L.'),
    Skill(id: 'mate.9-11.dinero', area: Area.matematicas, band: AgeBand.b9a11, nombre: 'Presupuesto', descripcion: 'Planea compras con un presupuesto, calcula el precio por unidad y los descuentos.'),
    Skill(id: 'mate.9-11.operaciones', area: Area.matematicas, band: AgeBand.b9a11, nombre: 'Operaciones', descripcion: 'Multiplica por una cifra, divide con resto, suma decimales y calcula fracciones de una cantidad.'),
    Skill(id: 'mate.9-11.tiempo', area: Area.matematicas, band: AgeBand.b9a11, nombre: 'Tiempo y duraciones', descripcion: 'Lee cualquier hora, calcula cuánto falta y a qué hora termina una actividad.'),
    Skill(id: 'mate.9-11.fracciones', area: Area.matematicas, band: AgeBand.b9a11, nombre: 'Fracciones equivalentes', descripcion: 'Reconoce fracciones equivalentes, suma fracciones de igual denominador y compara fracciones distintas.'),
    Skill(id: 'mate.9-11.area', area: Area.matematicas, band: AgeBand.b9a11, nombre: 'Área y perímetro', descripcion: 'Calcula áreas contando, con medidas y en figuras compuestas, y distingue el área del perímetro.'),

    // Lenguaje y lectura
    Skill(id: 'lengua.3-4.vocales', area: Area.lenguaje, band: AgeBand.b3a4, nombre: 'Sonido inicial', descripcion: 'Reconoce las palabras que empiezan con el mismo sonido de vocal.'),
    Skill(id: 'lengua.3-4.cuentos', area: Area.lenguaje, band: AgeBand.b3a4, nombre: 'Escuchar cuentos', descripcion: 'Sigue un cuento corto y responde qué pasó.'),
    Skill(id: 'lengua.3-4.trazos', area: Area.lenguaje, band: AgeBand.b3a4, nombre: 'Trazos y primeras letras', descripcion: 'Sigue con el dedo líneas, vocales y números en el orden y la dirección de la guía.'),
    Skill(id: 'lengua.5-6.sonidos', area: Area.lenguaje, band: AgeBand.b5a6, nombre: 'Conciencia fonológica', descripcion: 'Reconoce el sonido inicial de las palabras y la letra con la que empiezan, y cuenta sílabas.'),
    Skill(id: 'lengua.5-6.escucha', area: Area.lenguaje, band: AgeBand.b5a6, nombre: 'Comprensión de cuentos', descripcion: 'Responde qué pasó, por qué y qué podría pasar en un cuento escuchado.'),
    Skill(id: 'lengua.5-6.alfabeto', area: Area.lenguaje, band: AgeBand.b5a6, nombre: 'Letras y sílabas', descripcion: 'Arma palabras letra por letra, sílaba por sílaba.'),
    Skill(id: 'lengua.5-6.lectura', area: Area.lenguaje, band: AgeBand.b5a6, nombre: 'Frases cortas', descripcion: 'Ordena las palabras de oraciones cortas con apoyo de la voz.'),
    Skill(id: 'lengua.5-6.trazo', area: Area.lenguaje, band: AgeBand.b5a6, nombre: 'Trazo de letras', descripcion: 'Traza letras y números en el orden y la dirección del trazo escolar.'),
    Skill(id: 'lengua.7-8.comprension', area: Area.lenguaje, band: AgeBand.b7a8, nombre: 'Lectura con comprensión', descripcion: 'Responde qué pasó, por qué y qué se puede inferir de un texto corto.'),
    Skill(id: 'lengua.7-8.ortografia', area: Area.lenguaje, band: AgeBand.b7a8, nombre: 'Ortografía', descripcion: 'Escribe palabras con letras que se confunden: b y v, ll y y, c, s y z, g y j, h.'),
    Skill(id: 'lengua.7-8.oraciones', area: Area.lenguaje, band: AgeBand.b7a8, nombre: 'Oraciones con sentido', descripcion: 'Ordena oraciones con sujeto, verbo y complementos.'),
    Skill(id: 'lengua.9-11.textos', area: Area.lenguaje, band: AgeBand.b9a11, nombre: 'Comprensión de textos', descripcion: 'Infiere ideas que el texto no dice de forma directa.'),
    Skill(id: 'lengua.9-11.tildes', area: Area.lenguaje, band: AgeBand.b9a11, nombre: 'Tildes', descripcion: 'Escribe palabras con tilde y con letras que se confunden.'),
    Skill(id: 'lengua.9-11.sintaxis', area: Area.lenguaje, band: AgeBand.b9a11, nombre: 'Oraciones complejas', descripcion: 'Ordena oraciones con conectores como porque, pero, cuando y aunque.'),

    // Ciencias y entorno
    Skill(id: 'ciencias.3-4.animales', area: Area.ciencias, band: AgeBand.b3a4, nombre: 'Animales y dónde viven', descripcion: 'Reconoce animales y dónde viven: la granja, el mar, la selva y otros lugares.'),
    Skill(id: 'ciencias.3-4.cuerpo', area: Area.ciencias, band: AgeBand.b3a4, nombre: 'Partes del cuerpo', descripcion: 'Nombra partes del cuerpo y dice para qué sirven.'),
    Skill(id: 'ciencias.3-4.naturaleza', area: Area.ciencias, band: AgeBand.b3a4, nombre: 'Día, noche y naturaleza', descripcion: 'Relaciona el día y la noche, el agua, el sol y las plantas con lo que pasa a su alrededor.'),
    Skill(id: 'ciencias.5-6.seresvivos', area: Area.ciencias, band: AgeBand.b5a6, nombre: 'Hábitats y grupos', descripcion: 'Dice dónde viven los animales y si son mamíferos, aves, peces, reptiles, anfibios o insectos.'),
    Skill(id: 'ciencias.5-6.sentidos', area: Area.ciencias, band: AgeBand.b5a6, nombre: 'Los cinco sentidos', descripcion: 'Relaciona cada sentido con su órgano y con lo que nos permite saber.'),
    Skill(id: 'ciencias.5-6.experimentos', area: Area.ciencias, band: AgeBand.b5a6, nombre: 'Observar y predecir', descripcion: 'Predice qué pasará en experimentos sencillos: flotar, imanes, mezclas y luz.'),
    Skill(id: 'ciencias.7-8.animales', area: Area.ciencias, band: AgeBand.b7a8, nombre: 'Grupos de animales', descripcion: 'Clasifica animales por su grupo y por cómo se mueven.'),
    Skill(id: 'ciencias.7-8.organos', area: Area.ciencias, band: AgeBand.b7a8, nombre: 'Órganos del cuerpo', descripcion: 'Ubica los órganos principales y sabe para qué sirven.'),
    Skill(id: 'ciencias.7-8.materia', area: Area.ciencias, band: AgeBand.b7a8, nombre: 'Materia y energía', descripcion: 'Explica los cambios de estado, las mezclas y cómo pasa el calor.'),
    Skill(id: 'ciencias.9-11.clasificacion', area: Area.ciencias, band: AgeBand.b9a11, nombre: 'Clasificación de seres vivos', descripcion: 'Clasifica animales por grupo y por ecosistema, también los que confunden, como la ballena o el murciélago.'),
    Skill(id: 'ciencias.9-11.cuerpo', area: Area.ciencias, band: AgeBand.b9a11, nombre: 'Sistemas del cuerpo', descripcion: 'Relaciona órganos con sistemas y con los hábitos que cuidan la salud.'),
    Skill(id: 'ciencias.9-11.metodo', area: Area.ciencias, band: AgeBand.b9a11, nombre: 'Método científico', descripcion: 'Formula hipótesis, identifica variables y saca conclusiones con evidencia.'),

    // Creatividad y motricidad (colorear libre y dibujo no evalúan nada)
    Skill(id: 'arte.5-6.colorearnumeros', area: Area.creatividad, band: AgeBand.b5a6, nombre: 'Colorear por números', descripcion: 'Relaciona cada zona con su número y termina la lámina.'),
    Skill(id: 'arte.7-8.pixel', area: Area.creatividad, band: AgeBand.b7a8, nombre: 'Pixel art y coordenadas', descripcion: 'Copia modelos casilla por casilla y completa figuras en espejo.'),
    Skill(id: 'arte.9-11.simetria', area: Area.creatividad, band: AgeBand.b9a11, nombre: 'Copiar y reflejar figuras', descripcion: 'Copia modelos grandes casilla por casilla y completa en espejo la mitad que falta.'),

    // Emociones y hábitos
    Skill(id: 'socio.3-4.emociones', area: Area.socioemocional, band: AgeBand.b3a4, nombre: 'Emociones básicas', descripcion: 'Reconoce la alegría, la tristeza, el enojo y el miedo en caras y situaciones.'),
    Skill(id: 'socio.3-4.rutinas', area: Area.socioemocional, band: AgeBand.b3a4, nombre: 'Rutinas', descripcion: 'Ordena los pasos de las rutinas de aseo, comida y sueño.'),
    Skill(id: 'socio.5-6.regulacion', area: Area.socioemocional, band: AgeBand.b5a6, nombre: 'Qué hacer con una emoción', descripcion: 'Nombra la emoción de una situación y elige una forma sana de calmarse.'),
    Skill(id: 'socio.5-6.rutinas', area: Area.socioemocional, band: AgeBand.b5a6, nombre: 'Pasos de la vida diaria', descripcion: 'Ordena los pasos de rutinas y tareas de la casa más largas.'),
    Skill(id: 'socio.5-6.turnos', area: Area.socioemocional, band: AgeBand.b5a6, nombre: 'Turnos y acuerdos', descripcion: 'Elige qué hacer cuando hay que esperar, compartir o resolver un desacuerdo.'),
    Skill(id: 'socio.7-8.emociones', area: Area.socioemocional, band: AgeBand.b7a8, nombre: 'Emociones en situaciones', descripcion: 'Reconoce el orgullo, la vergüenza o los nervios en situaciones y elige qué ayuda.'),
    Skill(id: 'socio.7-8.seguridad', area: Area.socioemocional, band: AgeBand.b7a8, nombre: 'Seguridad en casa, en la calle y en internet', descripcion: 'Reconoce situaciones de riesgo y pide ayuda a un adulto de confianza.'),
    Skill(id: 'socio.9-11.decisiones', area: Area.socioemocional, band: AgeBand.b9a11, nombre: 'Equipo, pantallas y seguridad en línea', descripcion: 'Decide bien en trabajos en grupo, con las pantallas, las compras en los juegos y los riesgos de internet.'),
  ];

  static Skill? byId(String id) {
    for (final Skill s in all) {
      if (s.id == id) {
        return s;
      }
    }
    return null;
  }

  static List<Skill> forArea(Area area) => all.where((Skill s) => s.area == area).toList();

  static List<Skill> forBand(AgeBand band) => all.where((Skill s) => s.band == band).toList();

  static List<Skill> forAreaAndBand(Area area, AgeBand band) => all.where((Skill s) => s.area == area && s.band == band).toList();
}
