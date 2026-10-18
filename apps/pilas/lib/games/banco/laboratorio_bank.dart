import '../../model/age_band.dart';
import 'bank_generator.dart';

/// Laboratorio guiado: el niño predice qué va a pasar y luego recibe la
/// explicación. Día y noche (3-4), flota o se hunde e imanes (5-6), estados de
/// la materia y mezclas (7-8), método científico (9-11).
class LaboratorioBank {
  LaboratorioBank._();

  /// Pistas que orientan sin descartar ninguna opción.
  static const Map<AgeBand, String> pistaGeneral = <AgeBand, String>{
    AgeBand.b3a4: 'Piensa en lo que ves cada día en la casa o en el parque.',
    AgeBand.b5a6: 'Imagina el experimento: ¿qué pasaría de verdad?',
    AgeBand.b7a8: 'Piensa si algo se calienta, se enfría, se mezcla o se separa.',
    AgeBand.b9a11: 'Recuerda los pasos: pregunta, hipótesis, experimento, análisis y conclusión.',
  };

  static const List<BankQuestion> all = <BankQuestion>[
    // ---------------------------------------------------------- 3 a 4: día y noche, naturaleza
    BankQuestion(AgeBand.b3a4, 1, '¿Qué vemos en el cielo de noche?', <String>['la luna', 'el sol', 'un arcoíris'], 0, 'De noche vemos la luna y las estrellas; el sol se ve de día.', emojis: <String>['1f319', '2600', '1f308'], promptEmoji: '1f303'),
    BankQuestion(AgeBand.b3a4, 1, '¿Qué vemos en el cielo de día?', <String>['las estrellas', 'el sol', 'la luna'], 1, 'De día el sol ilumina todo.', emojis: <String>['2b50', '2600', '1f319'], promptEmoji: '1f305'),
    BankQuestion(AgeBand.b3a4, 1, '¿Cuándo dormimos?', <String>['al mediodía', 'en el desayuno', 'de noche'], 2, 'Dormimos de noche, cuando está oscuro.', emojis: <String>['2600', '1f95e', '1f319'], promptEmoji: '1f634'),
    BankQuestion(AgeBand.b3a4, 2, '¿Qué animal sale de noche?', <String>['el búho', 'la gallina', 'la mariposa'], 0, 'El búho caza de noche; por eso tiene ojos tan grandes.', emojis: <String>['1f989', '1f414', '1f98b'], promptEmoji: '1f319'),
    BankQuestion(AgeBand.b3a4, 2, 'Si dejas una planta sin agua muchos días, ¿qué pasa?', <String>['crece más', 'se marchita', 'cambia de color a azul'], 1, 'Las plantas necesitan agua; sin ella se marchitan.', emojis: <String>['1f331', '1f342', '1f535'], promptEmoji: '1fab4'),
    BankQuestion(AgeBand.b3a4, 2, '¿Qué necesita una semilla para crecer?', <String>['dulces', 'juguetes', 'agua y sol'], 2, 'La semilla necesita tierra, agua y luz del sol.', emojis: <String>['1f36c', '1f9f8', '1f4a7'], promptEmoji: '1f331'),
    BankQuestion(AgeBand.b3a4, 3, 'Si llueve mucho, ¿qué pasa con el charco?', <String>['se hace más grande', 'desaparece', 'se vuelve de hielo'], 0, 'Con más lluvia cae más agua y el charco crece.', emojis: <String>['1f30a', '274c', '1f9ca'], promptEmoji: '1f327'),
    BankQuestion(AgeBand.b3a4, 3, 'Si sale el sol fuerte, ¿qué le pasa al charco?', <String>['crece', 'se seca poco a poco', 'se vuelve leche'], 1, 'El sol calienta el agua y se evapora: el charco se seca.', emojis: <String>['1f30a', '2600', '1f95b'], promptEmoji: '1f4a7'),
    BankQuestion(AgeBand.b3a4, 3, '¿Qué pasa si sueltas una pelota en el aire?', <String>['se queda flotando', 'sube al cielo', 'cae al suelo'], 2, 'Todo lo que soltamos cae al suelo: eso es la gravedad.', emojis: <String>['1f388', '2601', '2b07'], promptEmoji: '26bd'),
    BankQuestion(AgeBand.b3a4, 4, 'Si pones hielo al sol, ¿qué pasa?', <String>['se derrite y se vuelve agua', 'se pone más duro', 'se vuelve piedra'], 0, 'El calor del sol derrite el hielo y lo convierte en agua.', emojis: <String>['1f4a7', '1f9ca', '1faa8'], promptEmoji: '1f9ca'),
    BankQuestion(AgeBand.b3a4, 4, '¿De dónde sale la sombra?', <String>['de la lluvia', 'de la luz que no pasa por tu cuerpo', 'del viento'], 1, 'La luz no puede atravesar tu cuerpo y detrás queda la sombra.', emojis: <String>['1f327', '1f9cd', '1f32c'], promptEmoji: '2600'),
    BankQuestion(AgeBand.b3a4, 4, '¿Qué pasa con una flor que recibe sol y agua?', <String>['se esconde', 'se duerme', 'crece y se abre'], 2, 'Con sol y agua la planta crece y la flor se abre.', emojis: <String>['1f648', '1f634', '1f33b'], promptEmoji: '1f331'),

    // ---------------------------------------------------------- 5 a 6: flota, imanes, luz, mezclas
    BankQuestion(AgeBand.b5a6, 1, 'Si pones una piedra en el agua, ¿qué pasa?', <String>['se hunde', 'flota', 'se derrite'], 0, 'La piedra es pesada para su tamaño y se hunde.', emojis: <String>['2b07', '1f30a', '1f4a7'], promptEmoji: '1faa8'),
    BankQuestion(AgeBand.b5a6, 1, 'Si pones una hoja seca en el agua, ¿qué pasa?', <String>['se hunde', 'flota', 'explota'], 1, 'La hoja es liviana y flota sobre el agua.', emojis: <String>['2b07', '1f30a', '1f4a5'], promptEmoji: '1f342'),
    BankQuestion(AgeBand.b5a6, 1, '¿Cuál de estos atrae un imán?', <String>['una hoja de papel', 'un palo de madera', 'un clip de metal'], 2, 'El imán atrae el hierro y el acero, como el clip; no atrae papel ni madera.', emojis: <String>['1f4c4', '1fab5', '1f4ce'], promptEmoji: '1f9f2'),
    BankQuestion(AgeBand.b5a6, 2, 'Si mezclas agua y aceite, ¿qué pasa?', <String>['el aceite queda arriba, separado', 'se mezclan y no se ven', 'el agua desaparece'], 0, 'El aceite es más liviano que el agua y no se mezcla: queda flotando encima.', emojis: <String>['1fad7', '1f300', '274c'], promptEmoji: '1f9ea'),
    BankQuestion(AgeBand.b5a6, 2, 'Si echas sal en un vaso de agua y revuelves, ¿qué pasa?', <String>['la sal flota', 'la sal se disuelve y no se ve', 'el agua se pone roja'], 1, 'La sal se disuelve en el agua: no la ves, pero el agua queda salada.', emojis: <String>['1f30a', '1f9c2', '1f534'], promptEmoji: '1f964'),
    BankQuestion(AgeBand.b5a6, 2, 'Si pones una cuchara en un vaso con agua y la miras de lado, ¿qué parece?', <String>['más larga', 'invisible', 'doblada'], 2, 'La luz cambia de dirección al pasar del agua al aire y la cuchara parece doblada.', emojis: <String>['1f4cf', '1f47b', '1f944'], promptEmoji: '1f964'),
    BankQuestion(AgeBand.b5a6, 3, 'Si tapas una planta con una caja oscura por una semana, ¿qué pasa?', <String>['se pone pálida y débil', 'crece igual', 'da frutos'], 0, 'Sin luz la planta no puede fabricar su alimento y se pone amarilla y débil.', emojis: <String>['1f342', '1f331', '1f34e'], promptEmoji: '1f4e6'),
    BankQuestion(AgeBand.b5a6, 3, 'Si soplas un molinillo de papel, ¿qué lo hace girar?', <String>['el calor', 'el aire que empuja las aspas', 'la luz'], 1, 'El aire en movimiento (el viento) empuja las aspas y las hace girar.', emojis: <String>['1f525', '1f32c', '2600'], promptEmoji: '1f32c'),
    BankQuestion(AgeBand.b5a6, 3, 'Si pones un globo inflado al sol fuerte, ¿qué pasa?', <String>['se encoge', 'se vuelve de hielo', 'se infla más'], 2, 'El aire caliente ocupa más espacio y el globo se infla un poco más (y puede estallar).', emojis: <String>['1f4a8', '1f9ca', '1f388'], promptEmoji: '1f388'),
    BankQuestion(AgeBand.b5a6, 4, '¿Cómo puedes hacer que una bola de plastilina flote?', <String>['dándole forma de barquito', 'haciéndola más redonda', 'mojándola primero'], 0, 'Con forma de barco, la misma plastilina ocupa más espacio y empuja más agua: flota.', emojis: <String>['26f5', '26aa', '1f4a7']),
    BankQuestion(AgeBand.b5a6, 4, 'Si pones una vela encendida bajo un vaso de vidrio, ¿qué pasa?', <String>['arde más fuerte', 'se apaga cuando se acaba el aire', 'el vaso se derrite'], 1, 'El fuego necesita el oxígeno del aire; cuando se acaba dentro del vaso, la vela se apaga.', emojis: <String>['1f525', '1f56f', '1f964'], promptEmoji: '1f56f'),
    BankQuestion(AgeBand.b5a6, 4, 'Si mezclas pintura amarilla con pintura azul, ¿qué color sale?', <String>['rojo', 'morado', 'verde'], 2, 'Amarillo y azul forman verde.', emojis: <String>['1f534', '1f7e3', '1f7e2'], promptEmoji: '1f3a8'),

    // ---------------------------------------------------------- 7 a 8: materia y energía
    BankQuestion(AgeBand.b7a8, 1, 'Si calientas agua hasta que hierve, ¿en qué se convierte?', <String>['en vapor (gas)', 'en hielo', 'en aceite'], 0, 'A 100 °C el agua hierve y pasa de líquido a gas: el vapor.'),
    BankQuestion(AgeBand.b7a8, 1, 'Si metes jugo al congelador, ¿en qué estado queda?', <String>['líquido', 'sólido', 'gaseoso'], 1, 'Al enfriarse por debajo de 0 °C el jugo se congela: se vuelve sólido.'),
    BankQuestion(AgeBand.b7a8, 1, '¿Qué pesa más: un kilo de algodón o un kilo de piedras?', <String>['el algodón', 'las piedras', 'pesan lo mismo'], 2, 'Un kilo es un kilo: el algodón ocupa más espacio, pero pesa igual.'),
    BankQuestion(AgeBand.b7a8, 2, 'Si cuelgas ropa mojada al sol, ¿a dónde se va el agua?', <String>['se evapora al aire', 'se mete en la tela para siempre', 'se convierte en sal'], 0, 'El sol calienta el agua, que se evapora y pasa al aire; por eso la ropa se seca.'),
    BankQuestion(AgeBand.b7a8, 2, '¿Cómo separarías arena mezclada con agua?', <String>['con un imán', 'con un filtro o colador', 'calentando el agua un poco'], 1, 'La arena no se disuelve: queda atrapada en el filtro y el agua pasa.'),
    BankQuestion(AgeBand.b7a8, 2, '¿Por qué el hielo flota en el agua?', <String>['porque es más caliente', 'porque está más sucio', 'porque es menos denso que el agua líquida'], 2, 'Al congelarse, el agua se expande y el hielo queda menos denso: por eso flota.'),
    BankQuestion(AgeBand.b7a8, 3, 'Si dejas una bicicleta bajo la lluvia muchos días, ¿qué le pasa al metal?', <String>['se oxida', 'se vuelve plástico', 'se hace más brillante'], 0, 'El hierro reacciona con el agua y el oxígeno y forma óxido (el color café).'),
    BankQuestion(AgeBand.b7a8, 3, '¿Qué pasa con el aire dentro de un globo si lo metes al congelador?', <String>['se expande', 'se encoge y el globo se desinfla un poco', 'se vuelve agua'], 1, 'El aire frío ocupa menos espacio; el globo se ve más pequeño.'),
    BankQuestion(AgeBand.b7a8, 3, '¿Por qué se empañan las ventanas cuando hace frío afuera?', <String>['por el polvo', 'porque el vidrio suda', 'porque el vapor del aire se condensa en el vidrio frío'], 2, 'El vapor de agua del aire se enfría al tocar el vidrio y vuelve a ser líquido: gotitas.'),
    BankQuestion(AgeBand.b7a8, 4, 'Dos cubos de hielo iguales: uno en un plato y otro envuelto en una toalla. ¿Cuál se derrite primero?', <String>['el del plato, porque el aire lo calienta', 'el de la toalla, porque la toalla lo calienta', 'los dos al mismo tiempo'], 0, 'La toalla no calienta: aísla, frena el paso del calor. El del plato recibe más calor del aire y se derrite antes.'),
    BankQuestion(AgeBand.b7a8, 4, '¿Qué es una mezcla?', <String>['una sola sustancia pura', 'dos o más sustancias juntas que se pueden separar', 'solo líquidos revueltos'], 1, 'En una mezcla las sustancias conservan sus propiedades y se pueden separar: arena y agua, cereal y leche.'),
    BankQuestion(AgeBand.b7a8, 4, 'Si pones una cuchara de metal y una de madera en una sopa caliente, ¿cuál se calienta más rápido?', <String>['la de madera', 'ninguna', 'la de metal'], 2, 'El metal conduce bien el calor; la madera es aislante.'),

    // ---------------------------------------------------------- 9 a 11: método científico
    BankQuestion(AgeBand.b9a11, 1, '¿Qué es una hipótesis?', <String>['una explicación posible que se puede poner a prueba', 'un resultado seguro', 'una opinión que no se puede comprobar'], 0, 'La hipótesis es una respuesta tentativa; el experimento sirve para ver si se sostiene.'),
    BankQuestion(AgeBand.b9a11, 1, 'Quieres saber si las plantas crecen más con música. ¿Qué debes mantener igual en las dos plantas?', <String>['solo la cantidad de música', 'el agua, la luz, la tierra y la maceta', 'nada, cada planta es distinta'], 1, 'Para que la comparación sea justa, todo debe ser igual menos lo que quieres probar: la música.'),
    BankQuestion(AgeBand.b9a11, 1, 'En ese experimento, ¿qué es lo único que cambias a propósito?', <String>['el agua', 'la luz', 'la música'], 2, 'La variable que cambias se llama variable independiente: aquí, la música.'),
    BankQuestion(AgeBand.b9a11, 2, '¿Para qué sirve la planta "sin música" en ese experimento?', <String>['es el control: permite comparar', 'para ahorrar música', 'no sirve para nada'], 0, 'El control muestra qué pasa sin el cambio; sin él no sabrías si la música influyó.'),
    BankQuestion(AgeBand.b9a11, 2, 'Si el resultado no coincide con tu hipótesis, ¿qué haces?', <String>['cambias los datos para que coincidan', 'revisas el experimento y, si está bien hecho, cambias la hipótesis', 'repites hasta que salga lo que querías'], 1, 'Los datos mandan: una hipótesis equivocada también enseña. Nunca se cambian los datos.'),
    BankQuestion(AgeBand.b9a11, 2, '¿Por qué conviene repetir un experimento varias veces?', <String>['para gastar más materiales', 'porque la primera vez no cuenta', 'para confiar en que el resultado no fue casualidad'], 2, 'Repetir permite ver si el resultado se mantiene o si fue un accidente.'),
    BankQuestion(AgeBand.b9a11, 3, 'Mides la temperatura del agua cada minuto mientras se calienta. ¿Cómo presentas mejor esos datos?', <String>['en una gráfica de líneas', 'en un dibujo', 'en una lista de palabras'], 0, 'Una gráfica de líneas muestra cómo cambia una cantidad con el tiempo.'),
    BankQuestion(AgeBand.b9a11, 3, '¿Cuál de estas es una observación y no una opinión?', <String>['el cielo es bonito hoy', 'la planta de la ventana mide 12 cm', 'me parece que lloverá'], 1, 'Una observación se puede medir o comprobar; "bonito" y "me parece" son opiniones.'),
    BankQuestion(AgeBand.b9a11, 3, 'Un amigo dice que su pulsera "atrae la buena suerte". ¿Cómo lo pondrías a prueba?', <String>['preguntándole si está seguro', 'creyéndole porque es tu amigo', 'comparando muchos días con y sin la pulsera, anotando resultados'], 2, 'Para probar una afirmación hay que comparar con y sin la causa, muchas veces, y anotar.'),
    BankQuestion(AgeBand.b9a11, 4, 'Tu experimento muestra que las plantas con música crecieron 1 cm más. ¿Qué puedes concluir?', <String>['que en este experimento la música pareció ayudar; habría que repetirlo', 'que toda la música hace crecer todas las plantas', 'que las plantas oyen'], 0, 'Un resultado pequeño en un solo experimento es una pista, no una ley: se concluye con prudencia y se repite.'),
    BankQuestion(AgeBand.b9a11, 4, '¿Qué significa que un resultado sea "reproducible"?', <String>['que se puede dibujar', 'que otras personas obtienen lo mismo al repetir el experimento', 'que salió bonito'], 1, 'La ciencia confía en resultados que cualquiera puede repetir y obtener.'),
    BankQuestion(AgeBand.b9a11, 4, '¿Cuál es el orden correcto del método científico?', <String>['conclusión, experimento, pregunta', 'experimento, pregunta, hipótesis', 'pregunta, hipótesis, experimento, análisis, conclusión'], 2, 'Primero la pregunta, luego una hipótesis, el experimento para probarla, el análisis de datos y la conclusión.'),
  ];
}
