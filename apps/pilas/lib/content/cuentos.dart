import '../model/age_band.dart';

/// Una página del cuento: texto y una escena de pictogramas.
class Pagina {
  const Pagina(this.texto, this.escena);

  final String texto;

  /// Códigos Twemoji que componen la escena (de uno a tres).
  final List<String> escena;
}

/// Pregunta de comprensión. Las opciones llevan texto y, para los que no
/// leen, un pictograma.
class PreguntaCuento {
  const PreguntaCuento(this.texto, this.opciones, this.correcta, this.explicacion, {this.pista});

  final String texto;
  final List<OpcionCuento> opciones;
  final int correcta;
  final String explicacion;
  final String? pista;
}

class OpcionCuento {
  const OpcionCuento(this.texto, [this.emoji]);

  final String texto;
  final String? emoji;
}

class Cuento {
  const Cuento({required this.id, required this.titulo, required this.band, required this.paginas, required this.preguntas, required this.portada, this.valor});

  final String id;
  final String titulo;
  final AgeBand band;
  final List<Pagina> paginas;
  final List<PreguntaCuento> preguntas;
  final String portada;

  /// Idea o valor que trabaja (para la ficha del adulto).
  final String? valor;
}

/// Cuentos originales de Pilas. Hablan de la vida cotidiana de niños de
/// Colombia y América Latina; cada uno trae tres preguntas de comprensión.
class CuentoBank {
  CuentoBank._();

  static const List<Cuento> all = <Cuento>[
    // ------------------------------------------------------------ 3 a 4 años
    Cuento(
      id: 'gallina_lluvia',
      titulo: 'La gallina y la lluvia',
      band: AgeBand.b3a4,
      portada: '1f414',
      valor: 'Cuidar a otros',
      paginas: <Pagina>[
        Pagina('La gallina Pepa tenía tres pollitos amarillos.', <String>['1f414', '1f423', '1f423']),
        Pagina('De pronto empezó a llover. ¡Plic, plac, plic!', <String>['1f327', '1f414']),
        Pagina('Pepa abrió sus alas y los pollitos se taparon debajo.', <String>['1f414', '2614']),
        Pagina('Cuando salió el sol, los pollitos salieron a jugar.', <String>['2600', '1f423', '1f423']),
      ],
      preguntas: <PreguntaCuento>[
        PreguntaCuento('¿Cuántos pollitos tenía Pepa?', <OpcionCuento>[OpcionCuento('Tres', '1f423'), OpcionCuento('Uno', '1f95a'), OpcionCuento('Muchos', '1f414')], 0, 'Pepa tenía tres pollitos amarillos.', pista: 'Al principio del cuento se dijo el número.'),
        PreguntaCuento('¿Qué pasó de pronto?', <OpcionCuento>[OpcionCuento('Nevó', '2744'), OpcionCuento('Llovió', '1f327'), OpcionCuento('Hizo viento', '1f32c')], 1, 'Empezó a llover: plic, plac, plic.'),
        PreguntaCuento('¿Con qué tapó Pepa a los pollitos?', <OpcionCuento>[OpcionCuento('Con un paraguas', '2602'), OpcionCuento('Con una hoja', '1f343'), OpcionCuento('Con sus alas', '1f414')], 2, 'Pepa abrió sus alas y los pollitos se taparon debajo.'),
      ],
    ),
    Cuento(
      id: 'oso_miel',
      titulo: 'El oso que compartió',
      band: AgeBand.b3a4,
      portada: '1f43b',
      valor: 'Compartir',
      paginas: <Pagina>[
        Pagina('El oso Tomás encontró un tarro de miel.', <String>['1f43b', '1f36f']),
        Pagina('La abeja Lila lo miraba con hambre.', <String>['1f41d', '1f440']),
        Pagina('Tomás le dio la mitad. "¡Gracias!", dijo Lila.', <String>['1f43b', '1f36f', '1f41d']),
        Pagina('Los dos comieron juntos bajo el árbol.', <String>['1f333', '1f43b', '1f41d']),
      ],
      preguntas: <PreguntaCuento>[
        PreguntaCuento('¿Qué encontró el oso?', <OpcionCuento>[OpcionCuento('Miel', '1f36f'), OpcionCuento('Una pelota', '26bd'), OpcionCuento('Un pez', '1f41f')], 0, 'Tomás encontró un tarro de miel.'),
        PreguntaCuento('¿Quién tenía hambre?', <OpcionCuento>[OpcionCuento('Un conejo', '1f407'), OpcionCuento('La abeja', '1f41d'), OpcionCuento('Un pájaro', '1f426')], 1, 'La abeja Lila miraba la miel con hambre.'),
        PreguntaCuento('¿Qué hizo Tomás?', <OpcionCuento>[OpcionCuento('Se escondió', '1f648'), OpcionCuento('Se fue corriendo', '1f3c3'), OpcionCuento('Compartió', '1f91d')], 2, 'Tomás le dio la mitad de la miel a Lila.'),
      ],
    ),
    Cuento(
      id: 'bota_perdida',
      titulo: 'La bota perdida',
      band: AgeBand.b3a4,
      portada: '1f462',
      valor: 'Pedir ayuda',
      paginas: <Pagina>[
        Pagina('Sara iba a salir a jugar, pero solo encontró una bota.', <String>['1f467', '1f462']),
        Pagina('Buscó debajo de la cama. ¡No estaba!', <String>['1f6cf', '2753']),
        Pagina('Le preguntó a su perro Max. Max movió la cola y corrió al jardín.', <String>['1f415', '1f33f']),
        Pagina('¡La bota estaba en la casita de Max! Sara se rio mucho.', <String>['1f462', '1f415', '1f602']),
      ],
      preguntas: <PreguntaCuento>[
        PreguntaCuento('¿Qué buscaba Sara?', <OpcionCuento>[OpcionCuento('Una bota', '1f462'), OpcionCuento('Un sombrero', '1f452'), OpcionCuento('Una pelota', '26bd')], 0, 'Sara buscaba su otra bota.'),
        PreguntaCuento('¿Dónde buscó primero?', <OpcionCuento>[OpcionCuento('En la cocina', '1f373'), OpcionCuento('Debajo de la cama', '1f6cf'), OpcionCuento('En el jardín', '1f33f')], 1, 'Primero buscó debajo de la cama y no estaba.'),
        PreguntaCuento('¿Quién tenía la bota?', <OpcionCuento>[OpcionCuento('Su mamá', '1f469'), OpcionCuento('Un gato', '1f408'), OpcionCuento('Max, el perro', '1f415')], 2, 'La bota estaba en la casita de Max, el perro.'),
      ],
    ),

    // ------------------------------------------------------------ 5 a 6 años
    Cuento(
      id: 'mango_vecina',
      titulo: 'El mango de la vecina',
      band: AgeBand.b5a6,
      portada: '1f96d',
      valor: 'Honestidad',
      paginas: <Pagina>[
        Pagina('En el patio de doña Rosa había un palo de mango lleno de frutas. Las ramas pasaban por encima de la casa de Juan.', <String>['1f333', '1f96d', '1f3e1']),
        Pagina('Un mango cayó en el patio de Juan. Olía delicioso. Juan pensó: "Nadie me vio".', <String>['1f96d', '1f466', '1f914']),
        Pagina('Pero Juan tocó la puerta de doña Rosa y le mostró el mango. "Se cayó en mi patio", le dijo.', <String>['1f6aa', '1f475', '1f96d']),
        Pagina('Doña Rosa sonrió. "Quédatelo, y toma otros dos para tu mamá". Ese mango fue el más dulce que Juan probó.', <String>['1f475', '1f96d', '1f60b']),
      ],
      preguntas: <PreguntaCuento>[
        PreguntaCuento('¿De quién era el palo de mango?', <OpcionCuento>[OpcionCuento('De doña Rosa', '1f475'), OpcionCuento('De Juan', '1f466'), OpcionCuento('De la escuela', '1f3eb')], 0, 'El palo de mango estaba en el patio de doña Rosa.'),
        PreguntaCuento('¿Qué pensó Juan cuando cayó el mango?', <OpcionCuento>[OpcionCuento('Que estaba podrido', '1f922'), OpcionCuento('Que nadie lo había visto', '1f440'), OpcionCuento('Que era de su mamá', '1f469')], 1, 'Juan pensó "nadie me vio", pero igual fue a decirle a doña Rosa.'),
        PreguntaCuento('¿Por qué el mango fue el más dulce?', <OpcionCuento>[OpcionCuento('Porque tenía azúcar', '1f36c'), OpcionCuento('Porque era muy grande', '1f4cf'), OpcionCuento('Porque Juan fue honesto', '1f60a')], 2, 'Juan dijo la verdad y doña Rosa se lo regaló con cariño: por eso le supo tan dulce.'),
      ],
    ),
    Cuento(
      id: 'colibri_valiente',
      titulo: 'El colibrí y el incendio',
      band: AgeBand.b5a6,
      portada: '1f426',
      valor: 'Hacer la parte de uno',
      paginas: <Pagina>[
        Pagina('Un día, el bosque empezó a arder. Todos los animales corrieron asustados hacia el río.', <String>['1f525', '1f333', '1f98c']),
        Pagina('Solo el colibrí Quino volaba hasta el río, tomaba una gotita de agua en el pico y la dejaba caer sobre el fuego.', <String>['1f426', '1f4a7', '1f525']),
        Pagina('El jaguar se burló: "¿Qué puedes hacer tú con una gota?". Quino respondió: "Yo hago mi parte".', <String>['1f406', '1f426', '1f4ac']),
        Pagina('Los demás se miraron. El elefante trajo agua con la trompa, los monos con hojas... y entre todos apagaron el fuego.', <String>['1f418', '1f412', '1f4a6']),
      ],
      preguntas: <PreguntaCuento>[
        PreguntaCuento('¿Qué pasó en el bosque?', <OpcionCuento>[OpcionCuento('Un incendio', '1f525'), OpcionCuento('Una fiesta', '1f389'), OpcionCuento('Una inundación', '1f30a')], 0, 'El bosque empezó a arder.'),
        PreguntaCuento('¿Qué llevaba el colibrí en el pico?', <OpcionCuento>[OpcionCuento('Una semilla', '1f330'), OpcionCuento('Una gota de agua', '1f4a7'), OpcionCuento('Una flor', '1f33a')], 1, 'Quino llevaba una gotita de agua cada vez.'),
        PreguntaCuento('¿Qué nos enseña Quino?', <OpcionCuento>[OpcionCuento('Que hay que correr rápido', '1f3c3'), OpcionCuento('Que los pequeños no pueden ayudar', '1f645'), OpcionCuento('Que cada uno puede hacer su parte', '1f91d')], 2, 'Aunque era pequeño, Quino hizo su parte y los demás lo siguieron.'),
      ],
    ),
    Cuento(
      id: 'chiva_fiesta',
      titulo: 'La chiva que no arrancaba',
      band: AgeBand.b5a6,
      portada: '1f68c',
      valor: 'Trabajo en equipo',
      paginas: <Pagina>[
        Pagina('La chiva de don Chepe iba llena de gente para la fiesta del pueblo: música, gallinas, bultos de panela y muchos niños.', <String>['1f68c', '1f3b6', '1f414']),
        Pagina('En la subida más empinada, la chiva tosió: ¡pum, pum, pum! Y se apagó.', <String>['26f0', '1f68c', '1f4a8']),
        Pagina('"¡Todos a empujar!", gritó una niña llamada Amparo. Hasta el perro empujó con la cabeza.', <String>['1f467', '1f4aa', '1f415']),
        Pagina('La chiva arrancó otra vez y llegaron a la fiesta cantando. Amparo fue la primera en bailar.', <String>['1f389', '1f483', '1f68c']),
      ],
      preguntas: <PreguntaCuento>[
        PreguntaCuento('¿A dónde iba la chiva?', <OpcionCuento>[OpcionCuento('A la fiesta del pueblo', '1f389'), OpcionCuento('Al hospital', '1f3e5'), OpcionCuento('Al mar', '1f30a')], 0, 'La chiva iba llena de gente para la fiesta del pueblo.'),
        PreguntaCuento('¿Dónde se apagó la chiva?', <OpcionCuento>[OpcionCuento('En el río', '1f30a'), OpcionCuento('En la subida', '26f0'), OpcionCuento('En la plaza', '26f2')], 1, 'Se apagó en la subida más empinada.'),
        PreguntaCuento('¿Cómo lograron que arrancara?', <OpcionCuento>[OpcionCuento('Llamaron a un mecánico', '1f527'), OpcionCuento('Esperaron a la mañana', '1f305'), OpcionCuento('Todos empujaron', '1f4aa')], 2, 'Amparo pidió que todos empujaran, y entre todos lo lograron.'),
      ],
    ),

    // ------------------------------------------------------------ 7 a 8 años
    Cuento(
      id: 'tortuga_rio',
      titulo: 'Las tortugas del río',
      band: AgeBand.b7a8,
      portada: '1f422',
      valor: 'Cuidar la naturaleza',
      paginas: <Pagina>[
        Pagina('Cada año, cuando bajaba el río, las tortugas salían de noche a poner sus huevos en la playa de arena. Camilo lo sabía porque su abuela se lo había contado.', <String>['1f422', '1f319', '1f3d6']),
        Pagina('Una tarde, Camilo vio a unos muchachos escarbando la arena con palos. "Los huevos se venden bien", decía uno. A Camilo se le apretó el estómago.', <String>['1f466', '1f95a', '1f61f']),
        Pagina('No gritó ni peleó. Corrió a buscar a su abuela y a don Elías, el guardaparques. Entre los tres hablaron con los muchachos y les explicaron que, sin huevos, en pocos años no habría tortugas.', <String>['1f475', '1f9d1', '1f4ac']),
        Pagina('Los muchachos se fueron. Semanas después, Camilo vio decenas de tortuguitas corriendo hacia el agua bajo la luna. Sintió que una parte de ese río era suya.', <String>['1f422', '1f422', '1f30a']),
      ],
      preguntas: <PreguntaCuento>[
        PreguntaCuento('¿Cuándo salían las tortugas a poner huevos?', <OpcionCuento>[OpcionCuento('Cuando bajaba el río, de noche'), OpcionCuento('En las mañanas de lluvia'), OpcionCuento('Cuando crecía el río')], 0, 'El cuento dice que salían de noche, cuando bajaba el río.'),
        PreguntaCuento('¿Por qué a Camilo se le apretó el estómago?', <OpcionCuento>[OpcionCuento('Porque tenía hambre'), OpcionCuento('Porque entendió que iban a sacar los huevos'), OpcionCuento('Porque le dio miedo el río')], 1, 'Se preocupó al ver que los muchachos escarbaban buscando huevos para venderlos.', pista: 'Piensa en lo que acababa de ver y oír.'),
        PreguntaCuento('¿Qué decisión tomó Camilo?', <OpcionCuento>[OpcionCuento('Pelear con los muchachos'), OpcionCuento('Esconder los huevos'), OpcionCuento('Buscar ayuda de adultos')], 2, 'En vez de pelear, buscó a su abuela y al guardaparques, y hablaron con los muchachos.'),
      ],
    ),
    Cuento(
      id: 'ruana_abuelo',
      titulo: 'La ruana del abuelo',
      band: AgeBand.b7a8,
      portada: '1f9e3',
      valor: 'Paciencia y esfuerzo',
      paginas: <Pagina>[
        Pagina('En Boyacá hace frío por las mañanas. El abuelo de Lucía tejía ruanas en un telar de madera que hacía "tac, tac" todo el día.', <String>['1f474', '1f9f6', '1f3d4']),
        Pagina('Lucía quiso tejer una para su mamá. El primer día se enredó la lana. El segundo, el tejido le quedó torcido. Quiso rendirse.', <String>['1f467', '1f9f6', '1f624']),
        Pagina('"Mira mis manos", dijo el abuelo, y le mostró los dedos llenos de callos. "Cada callo es una ruana que me salió mal antes de que me saliera bien".', <String>['1f474', '270b', '1f4ac']),
        Pagina('Lucía tejió todas las tardes durante un mes. La ruana quedó un poco corta de un lado, pero su mamá no se la quitó en toda la semana.', <String>['1f469', '1f9e3', '2764']),
      ],
      preguntas: <PreguntaCuento>[
        PreguntaCuento('¿Qué hacía el abuelo de Lucía?', <OpcionCuento>[OpcionCuento('Tejía ruanas en un telar'), OpcionCuento('Vendía lana en el mercado'), OpcionCuento('Cuidaba ovejas')], 0, 'El abuelo tejía ruanas en un telar de madera.'),
        PreguntaCuento('¿Qué quería decir el abuelo con sus callos?', <OpcionCuento>[OpcionCuento('Que tejer duele mucho'), OpcionCuento('Que equivocarse es parte de aprender'), OpcionCuento('Que Lucía debía ponerse guantes')], 1, 'Cada callo era una ruana que le había salido mal antes de salirle bien: aprender toma errores y tiempo.', pista: 'El abuelo hablaba de las ruanas que le salieron mal.'),
        PreguntaCuento('¿Cómo sabemos que a la mamá le gustó la ruana?', <OpcionCuento>[OpcionCuento('Porque la guardó en el armario'), OpcionCuento('Porque dijo que estaba perfecta'), OpcionCuento('Porque no se la quitó en toda la semana')], 2, 'Aunque quedó un poco corta, la mamá la usó toda la semana.'),
      ],
    ),
    Cuento(
      id: 'bicicleta_prestada',
      titulo: 'La bicicleta prestada',
      band: AgeBand.b7a8,
      portada: '1f6b2',
      valor: 'Responsabilidad',
      paginas: <Pagina>[
        Pagina('Mateo no tenía bicicleta, pero su vecina Valentina le prestó la suya para la ciclovía del domingo. "Cuídamela", le dijo.', <String>['1f466', '1f6b2', '1f467']),
        Pagina('Mateo dio vueltas felices por toda la avenida. En una curva, quiso hacer una pirueta y la bicicleta se raspó contra el andén. El timón quedó torcido.', <String>['1f6b2', '1f4a5', '1f630']),
        Pagina('Pensó en devolverla sin decir nada. Pero esa noche no pudo dormir. Al día siguiente, le contó todo a Valentina y le ofreció arreglarla con sus ahorros.', <String>['1f634', '1f4ac', '1f4b0']),
        Pagina('Valentina se puso brava un rato, pero luego dijo: "Gracias por decirme la verdad". Arreglaron el timón juntos en el taller de la esquina.', <String>['1f527', '1f6b2', '1f91d']),
      ],
      preguntas: <PreguntaCuento>[
        PreguntaCuento('¿Por qué Mateo tenía la bicicleta de Valentina?', <OpcionCuento>[OpcionCuento('Ella se la prestó para la ciclovía'), OpcionCuento('Se la encontró en el parque'), OpcionCuento('Se la compró con sus ahorros')], 0, 'Valentina se la prestó para la ciclovía del domingo.'),
        PreguntaCuento('¿Por qué Mateo no pudo dormir?', <OpcionCuento>[OpcionCuento('Porque le dolía la rodilla'), OpcionCuento('Porque se sentía mal por pensar en ocultar el daño'), OpcionCuento('Porque quería seguir montando')], 1, 'Pensó en devolverla sin decir nada y eso lo tenía intranquilo.', pista: 'Piensa en lo que Mateo había pensado hacer.'),
        PreguntaCuento('¿Qué hizo Mateo para reparar el daño?', <OpcionCuento>[OpcionCuento('Compró otra bicicleta'), OpcionCuento('Le pidió a su papá que la pagara'), OpcionCuento('Contó la verdad y ayudó a arreglarla')], 2, 'Le contó todo a Valentina y arreglaron el timón juntos.'),
      ],
    ),

    // ------------------------------------------------------------ 9 a 11 años
    Cuento(
      id: 'frailejon',
      titulo: 'El páramo de Teresa',
      band: AgeBand.b9a11,
      portada: '1f3d4',
      valor: 'Pensar en el futuro',
      paginas: <Pagina>[
        Pagina('Teresa vivía en una vereda a tres mil quinientos metros de altura, donde las nubes caminaban a ras del suelo. Su papá sembraba papa en una ladera que cada año subía un poco más hacia el páramo, porque la tierra de abajo se cansaba.', <String>['1f3d4', '2601', '1f954']),
        Pagina('En la escuela, la profesora explicó que los frailejones, esas plantas peludas que parecen soldados dormidos, atrapan el agua de la niebla y la dejan escurrir hacia los ríos. "Sin páramo, Bogotá tendría sed", dijo.', <String>['1f33f', '1f4a7', '1f3d9']),
        Pagina('Esa noche, Teresa hizo una cuenta: un frailejón crece un centímetro al año. Los que su papá había quemado para sembrar la nueva parcela medían más que ella. Tenían más años que su abuelo.', <String>['1f4cf', '1f525', '1f474']),
        Pagina('No lo regañó. Le mostró el cuaderno con los números y le preguntó cuánta agua bajaría al pueblo dentro de veinte años. Su papá se quedó callado un buen rato. Al mes siguiente, la familia empezó a sembrar en la tierra de abajo, con abono de la vaca, y dejaron el páramo en paz.', <String>['1f4d3', '1f468', '1f404']),
      ],
      preguntas: <PreguntaCuento>[
        PreguntaCuento('¿Por qué el papá de Teresa sembraba cada año más arriba?', <OpcionCuento>[OpcionCuento('Porque la tierra de abajo se agotaba'), OpcionCuento('Porque arriba llovía menos'), OpcionCuento('Porque el gobierno se lo ordenó')], 0, 'El cuento dice que la tierra de abajo "se cansaba", es decir, se agotaba.'),
        PreguntaCuento('¿Qué quiso decir la profesora con "sin páramo, Bogotá tendría sed"?', <OpcionCuento>[OpcionCuento('Que en Bogotá hace mucho calor'), OpcionCuento('Que el agua de la ciudad viene del páramo'), OpcionCuento('Que los frailejones se beben el agua')], 1, 'Los frailejones atrapan el agua de la niebla y la sueltan hacia los ríos que abastecen la ciudad.', pista: 'Relee lo que hacen los frailejones con la niebla.'),
        PreguntaCuento('¿Por qué funcionó la estrategia de Teresa?', <OpcionCuento>[OpcionCuento('Porque lloró hasta convencerlo'), OpcionCuento('Porque amenazó con llamar a la policía'), OpcionCuento('Porque le mostró datos y lo hizo pensar en el futuro')], 2, 'En vez de regañarlo, le mostró números y le hizo una pregunta sobre el futuro del pueblo.'),
      ],
    ),
    Cuento(
      id: 'emisora',
      titulo: 'La emisora del colegio',
      band: AgeBand.b9a11,
      portada: '1f399',
      valor: 'Escuchar a los demás',
      paginas: <Pagina>[
        Pagina('Cuando el rector anunció que el colegio tendría una emisora en el descanso, Daniel supo que quería ser el locutor. Hablaba rápido, contaba chistes y conocía todas las canciones de moda.', <String>['1f399', '1f466', '1f3b6']),
        Pagina('La primera semana fue un éxito. La segunda, notó que varios niños de primero se tapaban los oídos y que la profesora de sexto pedía bajar el volumen. Un compañero le dijo: "Solo pones lo que te gusta a ti".', <String>['1f509', '1f9d2', '1f4ac']),
        Pagina('Daniel se ofendió. Pero esa tarde, en el bus, se dio cuenta de que él también se ponía audífonos cuando el chofer subía su música. Entendió algo incómodo: una emisora no es para que uno hable, es para que los demás escuchen.', <String>['1f68c', '1f3a7', '1f4a1']),
        Pagina('Puso un buzón de cartón con un letrero: "¿Qué quieres oír?". Llegaron pedidos de cumbia, de un cuento para los pequeños y de cinco minutos de silencio para los que querían leer. Daniel los cumplió todos. La emisora nunca volvió a sonar tan fuerte, pero nunca tuvo tantos oyentes.', <String>['1f4ec', '1f4fb', '1f4da']),
      ],
      preguntas: <PreguntaCuento>[
        PreguntaCuento('¿Qué señales le mostraron a Daniel que algo no iba bien?', <OpcionCuento>[OpcionCuento('Los niños se tapaban los oídos y pedían bajar el volumen'), OpcionCuento('El rector cerró la emisora'), OpcionCuento('Se dañó el micrófono')], 0, 'Varios niños se tapaban los oídos y una profesora pedía bajar el volumen.'),
        PreguntaCuento('¿Qué entendió Daniel en el bus?', <OpcionCuento>[OpcionCuento('Que debía comprar mejores audífonos'), OpcionCuento('Que una emisora existe para quienes escuchan, no para quien habla'), OpcionCuento('Que la música del chofer era mejor')], 1, 'Al sentir lo mismo que sus oyentes, comprendió que la emisora es para los que escuchan.', pista: 'Piensa en qué hizo Daniel cuando el chofer subió la música.'),
        PreguntaCuento('¿Qué significa la última frase, "nunca tuvo tantos oyentes"?', <OpcionCuento>[OpcionCuento('Que la emisora se volvió aburrida'), OpcionCuento('Que Daniel dejó de ser locutor'), OpcionCuento('Que al escuchar a los demás, más gente quiso oírla')], 2, 'Cuando la emisora empezó a atender lo que pedían los demás, ganó oyentes aunque sonara más bajito.'),
      ],
    ),
    Cuento(
      id: 'mapa_barrio',
      titulo: 'El mapa de los charcos',
      band: AgeBand.b9a11,
      portada: '1f5fa',
      valor: 'Usar lo que uno sabe para resolver problemas',
      paginas: <Pagina>[
        Pagina('Cada vez que llovía fuerte, la calle de la escuela de Sofía se convertía en un río café. Los carros salpicaban a los niños y, una vez, una moto resbaló frente a la puerta.', <String>['1f327', '1f6e3', '1f3eb']),
        Pagina('En clase de matemáticas estaban aprendiendo a hacer gráficas. Sofía tuvo una idea: durante un mes, ella y tres amigos midieron con una regla la profundidad de los charcos en diez puntos de la calle y anotaron la hora.', <String>['1f4cf', '1f4ca', '1f467']),
        Pagina('Descubrieron un patrón. El charco más hondo se formaba siempre en la esquina de la panadería, donde una alcantarilla estaba tapada con bolsas y hojas. Nadie lo había notado porque el agua lo cubría todo.', <String>['1f50d', '1f5d1', '1f343']),
        Pagina('Llevaron el mapa y las gráficas a la junta del barrio. Un vecino consiguió una pala, otro habló con la alcaldía, y la panadería prometió barrer su esquina. En la siguiente lluvia, la calle siguió mojada, pero ya no fue un río.', <String>['1f5fa', '1f9d1', '1f31f']),
      ],
      preguntas: <PreguntaCuento>[
        PreguntaCuento('¿Cuál era el problema de la calle de la escuela?', <OpcionCuento>[OpcionCuento('Se inundaba cuando llovía fuerte'), OpcionCuento('Tenía demasiados carros'), OpcionCuento('No tenía panadería')], 0, 'Cada lluvia fuerte convertía la calle en un río café.'),
        PreguntaCuento('¿Qué permitió descubrir el patrón?', <OpcionCuento>[OpcionCuento('Preguntarle al panadero'), OpcionCuento('Medir y anotar los datos durante un mes'), OpcionCuento('Esperar a que dejara de llover')], 1, 'Midieron la profundidad de los charcos en diez puntos durante un mes y así vieron dónde se formaba el más hondo.', pista: 'Recuerda qué hicieron Sofía y sus amigos con la regla.'),
        PreguntaCuento('¿Por qué el cuento termina diciendo que la calle "siguió mojada, pero ya no fue un río"?', <OpcionCuento>[OpcionCuento('Porque la solución no sirvió'), OpcionCuento('Porque dejó de llover en el barrio'), OpcionCuento('Porque el problema mejoró aunque no desapareció del todo')], 2, 'La lluvia sigue mojando la calle, pero destapar la alcantarilla evitó la inundación: una mejora real, no mágica.'),
      ],
    ),
  ];

  static List<Cuento> forBand(AgeBand band) => all.where((Cuento c) => c.band == band).toList();
}
