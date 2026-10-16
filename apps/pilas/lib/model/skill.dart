import 'age_band.dart';
import 'area.dart';

/// Una habilidad del mapa por edad. Cada juego apunta a una habilidad por tramo.
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

  /// Qué sabe hacer el niño cuando la logra.
  final String descripcion;
}

/// Catálogo completo del mapa de habilidades (genérico latinoamericano).
class SkillCatalog {
  SkillCatalog._();

  static const List<Skill> all = <Skill>[
    // Razonamiento y lógica
    Skill(id: 'logica.3-4.emparejar', area: Area.logica, band: AgeBand.b3a4, nombre: 'Emparejar y recordar', descripcion: 'Encuentra pares iguales y recuerda dónde estaban.'),
    Skill(id: 'logica.3-4.clasificar', area: Area.logica, band: AgeBand.b3a4, nombre: 'Clasificar por color y forma', descripcion: 'Agrupa objetos por un atributo y detecta el que no pertenece.'),
    Skill(id: 'logica.3-4.secuencias', area: Area.logica, band: AgeBand.b3a4, nombre: 'Secuencias de dos', descripcion: 'Continúa patrones simples del tipo rojo, azul, rojo, azul.'),
    Skill(id: 'logica.3-4.caminos', area: Area.logica, band: AgeBand.b3a4, nombre: 'Seguir un camino', descripcion: 'Lleva un personaje por un camino sencillo hasta la meta.'),
    Skill(id: 'logica.3-4.encajar', area: Area.logica, band: AgeBand.b3a4, nombre: 'Encajar formas', descripcion: 'Coloca piezas en su silueta.'),
    Skill(id: 'logica.5-6.patrones3', area: Area.logica, band: AgeBand.b5a6, nombre: 'Patrones de tres', descripcion: 'Continúa y nombra patrones ABC y ABB.'),
    Skill(id: 'logica.5-6.quesobra', area: Area.logica, band: AgeBand.b5a6, nombre: 'Qué sobra', descripcion: 'Explica por qué un elemento no pertenece al grupo.'),
    Skill(id: 'logica.5-6.laberintos', area: Area.logica, band: AgeBand.b5a6, nombre: 'Laberintos simples', descripcion: 'Planea un camino con desvíos y callejones.'),
    Skill(id: 'logica.5-6.memoria', area: Area.logica, band: AgeBand.b5a6, nombre: 'Memoria de trabajo', descripcion: 'Recuerda la posición de hasta 12 cartas.'),
    Skill(id: 'logica.5-6.tangram', area: Area.logica, band: AgeBand.b5a6, nombre: 'Rotar y encajar', descripcion: 'Gira piezas para completar una figura.'),
    Skill(id: 'logica.5-6.sudoku4', area: Area.logica, band: AgeBand.b5a6, nombre: 'Sudoku de figuras 4 por 4', descripcion: 'Completa cuadrículas donde nada se repite en fila ni columna.'),
    Skill(id: 'logica.7-8.sudoku', area: Area.logica, band: AgeBand.b7a8, nombre: 'Sudokus de figuras', descripcion: 'Deduce la figura que falta en cuadrículas de 6 por 6.'),
    Skill(id: 'logica.7-8.tablas', area: Area.logica, band: AgeBand.b7a8, nombre: 'Lógica de tablas', descripcion: 'Cruza dos criterios para encontrar el elemento correcto.'),
    Skill(id: 'logica.7-8.planificar', area: Area.logica, band: AgeBand.b7a8, nombre: 'Planificar tres pasos', descripcion: 'Anticipa varios movimientos antes de actuar.'),
    Skill(id: 'logica.7-8.memoria', area: Area.logica, band: AgeBand.b7a8, nombre: 'Memoria con conceptos', descripcion: 'Empareja un concepto con su ejemplo.'),
    Skill(id: 'logica.7-8.patrones', area: Area.logica, band: AgeBand.b7a8, nombre: 'Patrones numéricos', descripcion: 'Descubre la regla de una serie de números.'),
    Skill(id: 'logica.9-11.acertijos', area: Area.logica, band: AgeBand.b9a11, nombre: 'Acertijos y deducción', descripcion: 'Resuelve problemas con varias pistas a la vez.'),
    Skill(id: 'logica.9-11.bloques', area: Area.logica, band: AgeBand.b9a11, nombre: 'Programación por bloques', descripcion: 'Ordena instrucciones para que un personaje llegue a la meta.'),
    Skill(id: 'logica.9-11.estrategia', area: Area.logica, band: AgeBand.b9a11, nombre: 'Estrategia', descripcion: 'Elige jugadas pensando en las consecuencias.'),
    Skill(id: 'logica.9-11.sudoku9', area: Area.logica, band: AgeBand.b9a11, nombre: 'Sudoku de números', descripcion: 'Resuelve sudokus de 6 por 6 y 9 por 9.'),
    Skill(id: 'logica.9-11.series', area: Area.logica, band: AgeBand.b9a11, nombre: 'Series con dos reglas', descripcion: 'Continúa series que combinan dos cambios.'),

    // Matemáticas
    Skill(id: 'mate.3-4.contar10', area: Area.matematicas, band: AgeBand.b3a4, nombre: 'Contar hasta 10', descripcion: 'Cuenta objetos y reconoce cantidades pequeñas.'),
    Skill(id: 'mate.3-4.masmenos', area: Area.matematicas, band: AgeBand.b3a4, nombre: 'Más y menos', descripcion: 'Compara dos grupos y dice cuál tiene más.'),
    Skill(id: 'mate.3-4.formas', area: Area.matematicas, band: AgeBand.b3a4, nombre: 'Formas básicas', descripcion: 'Reconoce círculo, cuadrado y triángulo.'),
    Skill(id: 'mate.5-6.numeros100', area: Area.matematicas, band: AgeBand.b5a6, nombre: 'Números hasta 100', descripcion: 'Lee, ordena y cuenta de 10 en 10.'),
    Skill(id: 'mate.5-6.sumas20', area: Area.matematicas, band: AgeBand.b5a6, nombre: 'Sumas y restas hasta 20', descripcion: 'Suma y resta con objetos y luego con números.'),
    Skill(id: 'mate.5-6.medidas', area: Area.matematicas, band: AgeBand.b5a6, nombre: 'Medidas comparadas', descripcion: 'Compara tamaños, pesos y cantidades: más, menos, igual.'),
    Skill(id: 'mate.5-6.reloj', area: Area.matematicas, band: AgeBand.b5a6, nombre: 'Reloj en punto', descripcion: 'Lee las horas en punto y las medias.'),
    Skill(id: 'mate.5-6.dinero', area: Area.matematicas, band: AgeBand.b5a6, nombre: 'Monedas y precios', descripcion: 'Paga precios exactos con monedas de 100, 200 y 500 pesos.'),
    Skill(id: 'mate.7-8.tablas', area: Area.matematicas, band: AgeBand.b7a8, nombre: 'Tablas de multiplicar', descripcion: 'Multiplica hasta 10 por 10 y divide sin resto.'),
    Skill(id: 'mate.7-8.fracciones', area: Area.matematicas, band: AgeBand.b7a8, nombre: 'Fracciones simples', descripcion: 'Reconoce mitades, tercios y cuartos en cosas reales.'),
    Skill(id: 'mate.7-8.dinero', area: Area.matematicas, band: AgeBand.b7a8, nombre: 'Dinero en pesos', descripcion: 'Paga con billetes y calcula las vueltas.'),
    Skill(id: 'mate.7-8.perimetro', area: Area.matematicas, band: AgeBand.b7a8, nombre: 'Perímetro', descripcion: 'Mide el contorno de una figura contando lados.'),
    Skill(id: 'mate.7-8.reloj', area: Area.matematicas, band: AgeBand.b7a8, nombre: 'Reloj con minutos', descripcion: 'Lee cuartos y minutos y calcula cuánto falta.'),
    Skill(id: 'mate.7-8.sumas100', area: Area.matematicas, band: AgeBand.b7a8, nombre: 'Sumas y restas hasta 100', descripcion: 'Resuelve operaciones con llevadas usando estrategias.'),
    Skill(id: 'mate.9-11.decimales', area: Area.matematicas, band: AgeBand.b9a11, nombre: 'Decimales', descripcion: 'Suma y compara números con coma, como precios.'),
    Skill(id: 'mate.9-11.fracciones', area: Area.matematicas, band: AgeBand.b9a11, nombre: 'Fracciones equivalentes', descripcion: 'Compara y suma fracciones con distinto denominador.'),
    Skill(id: 'mate.9-11.area', area: Area.matematicas, band: AgeBand.b9a11, nombre: 'Área y ángulos', descripcion: 'Calcula áreas contando y reconoce ángulos.'),
    Skill(id: 'mate.9-11.graficas', area: Area.matematicas, band: AgeBand.b9a11, nombre: 'Gráficas y promedios', descripcion: 'Lee gráficas de barras y calcula promedios.'),
    Skill(id: 'mate.9-11.operaciones', area: Area.matematicas, band: AgeBand.b9a11, nombre: 'Operaciones con números grandes', descripcion: 'Multiplica y divide con dos cifras.'),
    Skill(id: 'mate.9-11.dinero', area: Area.matematicas, band: AgeBand.b9a11, nombre: 'Presupuesto', descripcion: 'Planea una compra con un presupuesto y calcula el cambio.'),

    // Lenguaje y lectura
    Skill(id: 'lengua.3-4.vocales', area: Area.lenguaje, band: AgeBand.b3a4, nombre: 'Vocales y sonidos iniciales', descripcion: 'Reconoce el sonido con el que empieza una palabra.'),
    Skill(id: 'lengua.3-4.vocabulario', area: Area.lenguaje, band: AgeBand.b3a4, nombre: 'Vocabulario', descripcion: 'Nombra animales, comidas y objetos de su entorno.'),
    Skill(id: 'lengua.3-4.cuentos', area: Area.lenguaje, band: AgeBand.b3a4, nombre: 'Escuchar cuentos', descripcion: 'Sigue un cuento corto y recuerda qué pasó.'),
    Skill(id: 'lengua.3-4.trazos', area: Area.lenguaje, band: AgeBand.b3a4, nombre: 'Trazos libres', descripcion: 'Hace líneas, ondas y bucles con el dedo.'),
    Skill(id: 'lengua.5-6.alfabeto', area: Area.lenguaje, band: AgeBand.b5a6, nombre: 'Alfabeto y sílabas', descripcion: 'Une sílabas para formar palabras.'),
    Skill(id: 'lengua.5-6.lectura', area: Area.lenguaje, band: AgeBand.b5a6, nombre: 'Lectura de palabras y frases', descripcion: 'Lee palabras y frases cortas con apoyo de voz.'),
    Skill(id: 'lengua.5-6.trazo', area: Area.lenguaje, band: AgeBand.b5a6, nombre: 'Trazo de letras', descripcion: 'Escribe letras y números con el orden de trazo escolar.'),
    Skill(id: 'lengua.5-6.sonidos', area: Area.lenguaje, band: AgeBand.b5a6, nombre: 'Conciencia fonológica', descripcion: 'Separa palabras en sílabas y reconoce rimas.'),
    Skill(id: 'lengua.7-8.comprension', area: Area.lenguaje, band: AgeBand.b7a8, nombre: 'Lectura con comprensión', descripcion: 'Responde qué pasó y por qué en un texto corto.'),
    Skill(id: 'lengua.7-8.ortografia', area: Area.lenguaje, band: AgeBand.b7a8, nombre: 'Ortografía básica', descripcion: 'Usa mayúsculas, puntos y las letras correctas.'),
    Skill(id: 'lengua.7-8.oraciones', area: Area.lenguaje, band: AgeBand.b7a8, nombre: 'Escribir oraciones', descripcion: 'Ordena palabras en oraciones con sentido y concordancia.'),
    Skill(id: 'lengua.7-8.vocabulario', area: Area.lenguaje, band: AgeBand.b7a8, nombre: 'Sinónimos y vocabulario', descripcion: 'Elige la palabra precisa según el contexto.'),
    Skill(id: 'lengua.9-11.textos', area: Area.lenguaje, band: AgeBand.b9a11, nombre: 'Comprensión de textos', descripcion: 'Infiere ideas que el texto no dice de forma directa.'),
    Skill(id: 'lengua.9-11.tildes', area: Area.lenguaje, band: AgeBand.b9a11, nombre: 'Tildes y verbos', descripcion: 'Acentúa correctamente y conjuga en pasado, presente y futuro.'),
    Skill(id: 'lengua.9-11.escritura', area: Area.lenguaje, band: AgeBand.b9a11, nombre: 'Resumen y escritura', descripcion: 'Resume un texto y escribe con un propósito.'),
    Skill(id: 'lengua.9-11.sintaxis', area: Area.lenguaje, band: AgeBand.b9a11, nombre: 'Oraciones complejas', descripcion: 'Construye oraciones con conectores y signos de puntuación.'),

    // Ciencias y entorno
    Skill(id: 'ciencias.3-4.animales', area: Area.ciencias, band: AgeBand.b3a4, nombre: 'Animales y su entorno', descripcion: 'Reconoce animales y dónde viven.'),
    Skill(id: 'ciencias.3-4.cuerpo', area: Area.ciencias, band: AgeBand.b3a4, nombre: 'Partes del cuerpo', descripcion: 'Señala y nombra las partes de su cuerpo.'),
    Skill(id: 'ciencias.3-4.diaynoche', area: Area.ciencias, band: AgeBand.b3a4, nombre: 'Día, noche y clima', descripcion: 'Relaciona el clima con la ropa y las actividades.'),
    Skill(id: 'ciencias.5-6.seresvivos', area: Area.ciencias, band: AgeBand.b5a6, nombre: 'Seres vivos y hábitats', descripcion: 'Clasifica animales y plantas por su hábitat.'),
    Skill(id: 'ciencias.5-6.sentidos', area: Area.ciencias, band: AgeBand.b5a6, nombre: 'Los cinco sentidos', descripcion: 'Relaciona cada sentido con su órgano.'),
    Skill(id: 'ciencias.5-6.experimentos', area: Area.ciencias, band: AgeBand.b5a6, nombre: 'Observar y predecir', descripcion: 'Predice qué pasará y comprueba.'),
    Skill(id: 'ciencias.7-8.ciclos', area: Area.ciencias, band: AgeBand.b7a8, nombre: 'Ciclos de vida', descripcion: 'Ordena las etapas de la vida de animales y plantas.'),
    Skill(id: 'ciencias.7-8.materia', area: Area.ciencias, band: AgeBand.b7a8, nombre: 'Estados de la materia', descripcion: 'Explica qué pasa con el agua al calentarla o enfriarla.'),
    Skill(id: 'ciencias.7-8.organos', area: Area.ciencias, band: AgeBand.b7a8, nombre: 'Órganos y alimentación', descripcion: 'Ubica los órganos principales y sabe qué los cuida.'),
    Skill(id: 'ciencias.9-11.cuerpo', area: Area.ciencias, band: AgeBand.b9a11, nombre: 'Sistemas del cuerpo', descripcion: 'Relaciona órganos con sistemas y funciones.'),
    Skill(id: 'ciencias.9-11.ecosistemas', area: Area.ciencias, band: AgeBand.b9a11, nombre: 'Ecosistemas', descripcion: 'Reconoce ecosistemas de Colombia y América Latina y sus especies.'),
    Skill(id: 'ciencias.9-11.metodo', area: Area.ciencias, band: AgeBand.b9a11, nombre: 'Método científico', descripcion: 'Formula hipótesis, prueba y concluye con evidencia.'),

    // Creatividad y motricidad
    Skill(id: 'arte.3-4.colorear', area: Area.creatividad, band: AgeBand.b3a4, nombre: 'Colorear con el dedo', descripcion: 'Pinta zonas grandes y controla el trazo.'),
    Skill(id: 'arte.3-4.pintar', area: Area.creatividad, band: AgeBand.b3a4, nombre: 'Pintar libre', descripcion: 'Crea dibujos con pinceles y sellos.'),
    Skill(id: 'arte.5-6.colorearnumeros', area: Area.creatividad, band: AgeBand.b5a6, nombre: 'Colorear por números y letras', descripcion: 'Relaciona cada zona con su número o letra.'),
    Skill(id: 'arte.5-6.dibujarformas', area: Area.creatividad, band: AgeBand.b5a6, nombre: 'Dibujar con formas', descripcion: 'Combina formas para crear figuras.'),
    Skill(id: 'arte.7-8.pixel', area: Area.creatividad, band: AgeBand.b7a8, nombre: 'Pixel art y coordenadas', descripcion: 'Ubica casillas por fila y columna y completa simetrías.'),
    Skill(id: 'arte.7-8.pasoapaso', area: Area.creatividad, band: AgeBand.b7a8, nombre: 'Dibujar paso a paso', descripcion: 'Sigue guías para dibujar personajes.'),
    Skill(id: 'arte.9-11.diseno', area: Area.creatividad, band: AgeBand.b9a11, nombre: 'Diseño de personajes', descripcion: 'Crea personajes con proporción y color.'),
    Skill(id: 'arte.9-11.simetria', area: Area.creatividad, band: AgeBand.b9a11, nombre: 'Simetría y composición', descripcion: 'Completa figuras simétricas y compone con equilibrio.'),

    // Socioemocional y hábitos
    Skill(id: 'socio.3-4.emociones', area: Area.socioemocional, band: AgeBand.b3a4, nombre: 'Emociones básicas', descripcion: 'Reconoce alegría, tristeza, enojo y miedo.'),
    Skill(id: 'socio.3-4.rutinas', area: Area.socioemocional, band: AgeBand.b3a4, nombre: 'Rutinas de aseo y sueño', descripcion: 'Sigue el orden de las rutinas del día.'),
    Skill(id: 'socio.5-6.turnos', area: Area.socioemocional, band: AgeBand.b5a6, nombre: 'Turnos, compartir y normas', descripcion: 'Elige qué hacer cuando hay que esperar o compartir.'),
    Skill(id: 'socio.5-6.regulacion', area: Area.socioemocional, band: AgeBand.b5a6, nombre: 'Qué hacer con una emoción', descripcion: 'Nombra la emoción y elige una forma de calmarse.'),
    Skill(id: 'socio.7-8.conflictos', area: Area.socioemocional, band: AgeBand.b7a8, nombre: 'Resolver conflictos', descripcion: 'Propone soluciones justas y escucha al otro.'),
    Skill(id: 'socio.7-8.seguridad', area: Area.socioemocional, band: AgeBand.b7a8, nombre: 'Seguridad en casa y en la calle', descripcion: 'Reconoce situaciones de riesgo y pide ayuda.'),
    Skill(id: 'socio.9-11.equipo', area: Area.socioemocional, band: AgeBand.b9a11, nombre: 'Trabajo en equipo', descripcion: 'Coopera, reparte tareas y acepta acuerdos.'),
    Skill(id: 'socio.9-11.pantallas', area: Area.socioemocional, band: AgeBand.b9a11, nombre: 'Pantallas, dinero y ambiente', descripcion: 'Toma decisiones de cuidado propio, del dinero y del planeta.'),
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

  static List<Skill> forAreaAndBand(Area area, AgeBand band) =>
      all.where((Skill s) => s.area == area && s.band == band).toList();
}
