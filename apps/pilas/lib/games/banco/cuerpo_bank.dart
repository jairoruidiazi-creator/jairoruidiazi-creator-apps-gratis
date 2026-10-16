import '../../model/age_band.dart';
import 'bank_generator.dart';

// Pictogramas de partes del cuerpo.
const String _ojo = '1f441';
const String _oreja = '1f442';
const String _nariz = '1f443';
const String _boca = '1f444';
const String _lengua = '1f445';
const String _mano = '270b';
const String _pie = '1f9b6';
const String _pierna = '1f9b5';
const String _brazo = '1f4aa';
const String _diente = '1f9b7';
const String _cerebro = '1f9e0';
const String _corazon = '1fac0';
const String _pulmones = '1fac1';
const String _hueso = '1f9b4';

/// Arma el cuerpo: partes, sentidos, órganos y sistemas.
class CuerpoBank {
  CuerpoBank._();

  static const List<BankQuestion> all = <BankQuestion>[
    // ---------------------------------------------------------- 3 a 4: partes y para qué sirven
    BankQuestion(AgeBand.b3a4, 1, '¿Con qué parte del cuerpo vemos?', <String>['el ojo', 'la oreja', 'la mano'], 0, 'Vemos con los ojos.', emojis: <String>[_ojo, _oreja, _mano]),
    BankQuestion(AgeBand.b3a4, 1, '¿Con qué parte del cuerpo oímos?', <String>['la boca', 'la oreja', 'el pie'], 1, 'Oímos con las orejas.', emojis: <String>[_boca, _oreja, _pie]),
    BankQuestion(AgeBand.b3a4, 1, '¿Con qué olemos las flores?', <String>['la mano', 'el ojo', 'la nariz'], 2, 'Olemos con la nariz.', emojis: <String>[_mano, _ojo, _nariz]),
    BankQuestion(AgeBand.b3a4, 2, '¿Con qué parte comemos?', <String>['la boca', 'la oreja', 'la pierna'], 0, 'Comemos con la boca y masticamos con los dientes.', emojis: <String>[_boca, _oreja, _pierna]),
    BankQuestion(AgeBand.b3a4, 2, '¿Con qué parte caminamos?', <String>['la mano', 'los pies', 'la nariz'], 1, 'Caminamos con los pies y las piernas.', emojis: <String>[_mano, _pie, _nariz]),
    BankQuestion(AgeBand.b3a4, 2, '¿Con qué parte aplaudimos?', <String>['los pies', 'los ojos', 'las manos'], 2, 'Aplaudimos con las manos.', emojis: <String>[_pie, _ojo, _mano]),
    BankQuestion(AgeBand.b3a4, 3, '¿Qué parte del cuerpo se cepilla después de comer?', <String>['los dientes', 'la oreja', 'el pie'], 0, 'Los dientes se cepillan después de comer para que no se dañen.', emojis: <String>[_diente, _oreja, _pie]),
    BankQuestion(AgeBand.b3a4, 3, '¿Cuál es la lengua?', <String>['la nariz', 'la lengua', 'el brazo'], 1, 'La lengua está dentro de la boca y con ella probamos los sabores.', emojis: <String>[_nariz, _lengua, _brazo]),
    BankQuestion(AgeBand.b3a4, 3, '¿Con qué parte cargamos la maleta?', <String>['la oreja', 'el ojo', 'los brazos'], 2, 'Cargamos con los brazos y las manos.', emojis: <String>[_oreja, _ojo, _brazo]),
    BankQuestion(AgeBand.b3a4, 4, '¿Qué parte del cuerpo late dentro del pecho?', <String>['el corazón', 'el pie', 'la oreja'], 0, 'El corazón late dentro del pecho: pon la mano y siéntelo.', emojis: <String>[_corazon, _pie, _oreja]),
    BankQuestion(AgeBand.b3a4, 4, '¿Con qué parte pensamos?', <String>['la mano', 'el cerebro', 'la boca'], 1, 'Pensamos con el cerebro, que está dentro de la cabeza.', emojis: <String>[_mano, _cerebro, _boca]),
    BankQuestion(AgeBand.b3a4, 4, '¿Qué parte es dura y sostiene el cuerpo por dentro?', <String>['la lengua', 'la nariz', 'los huesos'], 2, 'Los huesos son duros y sostienen el cuerpo.', emojis: <String>[_lengua, _nariz, _hueso]),

    // ---------------------------------------------------------- 5 a 6: los cinco sentidos
    BankQuestion(AgeBand.b5a6, 1, '¿Con qué sentido sabes que el limón es ácido?', <String>['el gusto', 'el oído', 'la vista'], 0, 'El gusto está en la lengua: con él sentimos lo dulce, lo salado, lo ácido y lo amargo.', emojis: <String>[_lengua, _oreja, _ojo]),
    BankQuestion(AgeBand.b5a6, 1, '¿Con qué sentido sabes que suena un tambor?', <String>['la vista', 'el oído', 'el olfato'], 1, 'El oído está en las orejas.', emojis: <String>[_ojo, _oreja, _nariz]),
    BankQuestion(AgeBand.b5a6, 1, '¿Con qué sentido sabes que el pan está caliente sin mirarlo?', <String>['la vista', 'el oído', 'el tacto'], 2, 'El tacto está en la piel, sobre todo en las manos: sentimos frío, calor, suave y áspero.', emojis: <String>[_ojo, _oreja, _mano]),
    BankQuestion(AgeBand.b5a6, 2, '¿Con qué sentido sabes de qué color es una flor?', <String>['la vista', 'el gusto', 'el tacto'], 0, 'Los colores los vemos con los ojos: la vista.', emojis: <String>[_ojo, _lengua, _mano]),
    BankQuestion(AgeBand.b5a6, 2, '¿Con qué sentido sabes que se está quemando la arepa?', <String>['el tacto', 'el olfato', 'la vista'], 1, 'El olfato, en la nariz, nos avisa del humo antes de verlo.', emojis: <String>[_mano, _nariz, _ojo]),
    BankQuestion(AgeBand.b5a6, 2, '¿Cuántos sentidos tenemos?', <String>['tres', 'dos', 'cinco'], 2, 'Tenemos cinco sentidos: vista, oído, olfato, gusto y tacto.', emojis: <String>['33-20e3', '32-20e3', '35-20e3']),
    BankQuestion(AgeBand.b5a6, 3, '¿Qué protege a los ojos del polvo?', <String>['las pestañas', 'los dientes', 'las uñas'], 0, 'Las pestañas y los párpados protegen los ojos.', emojis: <String>[_ojo, _diente, _mano]),
    BankQuestion(AgeBand.b5a6, 3, '¿Qué órgano respira el aire que entra por la nariz?', <String>['el corazón', 'los pulmones', 'los huesos'], 1, 'El aire entra por la nariz y llega a los pulmones.', emojis: <String>[_corazon, _pulmones, _hueso]),
    BankQuestion(AgeBand.b5a6, 3, '¿Qué sentido usamos para leer un cuento?', <String>['el olfato', 'el gusto', 'la vista'], 2, 'Para leer usamos la vista; las personas ciegas leen con el tacto, en braille.', emojis: <String>[_nariz, _lengua, _ojo]),
    BankQuestion(AgeBand.b5a6, 4, '¿Qué órgano manda a todo el cuerpo y guarda los recuerdos?', <String>['el cerebro', 'el pie', 'la lengua'], 0, 'El cerebro recibe lo que sienten los sentidos y decide qué hacer.', emojis: <String>[_cerebro, _pie, _lengua]),
    BankQuestion(AgeBand.b5a6, 4, 'Si cierras los ojos y te dan una fruta, ¿con qué sentidos puedes saber cuál es?', <String>['solo con la vista', 'con el olfato, el tacto y el gusto', 'con ninguno'], 1, 'Sin ver, puedes olerla, tocarla y probarla.', emojis: <String>[_ojo, _nariz, '274c']),
    BankQuestion(AgeBand.b5a6, 4, '¿Qué parte del cuerpo bombea la sangre?', <String>['los pulmones', 'el cerebro', 'el corazón'], 2, 'El corazón bombea la sangre a todo el cuerpo.', emojis: <String>[_pulmones, _cerebro, _corazon]),

    // ---------------------------------------------------------- 7 a 8: órganos
    BankQuestion(AgeBand.b7a8, 1, '¿Qué órgano bombea la sangre a todo el cuerpo?', <String>['el corazón', 'el estómago', 'el cerebro'], 0, 'El corazón es un músculo que late unas 90 veces por minuto en un niño.', emojis: <String>[_corazon, '1f372', _cerebro]),
    BankQuestion(AgeBand.b7a8, 1, '¿Con qué órganos respiramos?', <String>['los riñones', 'los pulmones', 'los huesos'], 1, 'Los pulmones toman el oxígeno del aire y sacan el dióxido de carbono.', emojis: <String>['1fa78', _pulmones, _hueso]),
    BankQuestion(AgeBand.b7a8, 1, '¿Dónde se mezcla la comida con los jugos que la deshacen?', <String>['en el corazón', 'en los pulmones', 'en el estómago'], 2, 'En el estómago la comida se mezcla con jugos gástricos y se deshace.', emojis: <String>[_corazon, _pulmones, '1f372']),
    BankQuestion(AgeBand.b7a8, 2, '¿Qué protege al cerebro?', <String>['el cráneo', 'las costillas', 'la piel'], 0, 'El cráneo es el hueso que rodea y protege el cerebro.', emojis: <String>['1f480', _hueso, _mano]),
    BankQuestion(AgeBand.b7a8, 2, '¿Qué huesos protegen el corazón y los pulmones?', <String>['los de las piernas', 'las costillas', 'los dedos'], 1, 'Las costillas forman una jaula que protege el corazón y los pulmones.', emojis: <String>[_pierna, _hueso, _mano]),
    BankQuestion(AgeBand.b7a8, 2, '¿Qué órgano es el más grande del cuerpo?', <String>['el corazón', 'el cerebro', 'la piel'], 2, 'La piel cubre todo el cuerpo: es el órgano más grande y nos protege.', emojis: <String>[_corazon, _cerebro, _mano]),
    BankQuestion(AgeBand.b7a8, 3, '¿Qué hacen los músculos?', <String>['mueven los huesos', 'digieren la comida', 'limpian la sangre'], 0, 'Los músculos se acortan y tiran de los huesos para movernos.', emojis: <String>[_brazo, '1f372', '1fa78']),
    BankQuestion(AgeBand.b7a8, 3, '¿Qué pasa cuando se caen los dientes de leche?', <String>['se caen para siempre', 'dejan espacio a los dientes definitivos', 'vuelven a salir iguales'], 1, 'Los dientes de leche se caen para dar espacio a los dientes definitivos, que duran toda la vida.', emojis: <String>['274c', _diente, '1f504']),
    BankQuestion(AgeBand.b7a8, 3, '¿Por qué nos late más rápido el corazón cuando corremos?', <String>['porque tenemos miedo', 'porque hace calor', 'porque los músculos necesitan más oxígeno'], 2, 'Al correr, los músculos piden más oxígeno y el corazón bombea más rápido para llevárselo.', emojis: <String>['1f628', '1f975', _corazon]),
    BankQuestion(AgeBand.b7a8, 4, '¿Qué órgano limpia la sangre y produce la orina?', <String>['los riñones', 'los pulmones', 'el estómago'], 0, 'Los riñones filtran la sangre y sacan los desechos en la orina.', emojis: <String>['1fa78', _pulmones, '1f372']),
    BankQuestion(AgeBand.b7a8, 4, '¿Para qué sirve la saliva?', <String>['para que la comida sepa dulce', 'para empezar a deshacer la comida y tragarla', 'para enfriar la boca'], 1, 'La saliva humedece la comida y empieza la digestión en la boca.', emojis: <String>['1f36c', _boca, '1f9ca']),
    BankQuestion(AgeBand.b7a8, 4, '¿Qué órgano recibe la información de los cinco sentidos?', <String>['el corazón', 'el estómago', 'el cerebro'], 2, 'Los sentidos envían señales por los nervios hasta el cerebro.', emojis: <String>[_corazon, '1f372', _cerebro]),

    // ---------------------------------------------------------- 9 a 11: sistemas y cuidado
    BankQuestion(AgeBand.b9a11, 1, '¿A qué sistema pertenecen el corazón y las venas?', <String>['circulatorio', 'digestivo', 'respiratorio'], 0, 'El sistema circulatorio lleva la sangre por el cuerpo: corazón, arterias y venas.'),
    BankQuestion(AgeBand.b9a11, 1, '¿A qué sistema pertenecen el estómago y los intestinos?', <String>['nervioso', 'digestivo', 'óseo'], 1, 'El sistema digestivo transforma la comida en nutrientes.'),
    BankQuestion(AgeBand.b9a11, 1, '¿A qué sistema pertenecen el cerebro y los nervios?', <String>['respiratorio', 'muscular', 'nervioso'], 2, 'El sistema nervioso recibe información y controla el cuerpo.'),
    BankQuestion(AgeBand.b9a11, 2, '¿Cuántos huesos tiene una persona adulta, aproximadamente?', <String>['206', '50', '1.000'], 0, 'Un adulto tiene 206 huesos; los bebés tienen más, porque algunos se unen al crecer.'),
    BankQuestion(AgeBand.b9a11, 2, '¿Qué transporta el oxígeno en la sangre?', <String>['las plaquetas', 'los glóbulos rojos', 'los glóbulos blancos'], 1, 'Los glóbulos rojos llevan el oxígeno gracias a la hemoglobina.'),
    BankQuestion(AgeBand.b9a11, 2, '¿Qué hacen los glóbulos blancos?', <String>['llevan azúcar', 'tapan las heridas', 'defienden el cuerpo de infecciones'], 2, 'Los glóbulos blancos atacan virus y bacterias.'),
    BankQuestion(AgeBand.b9a11, 3, '¿Cuántas horas debe dormir un niño de 10 años?', <String>['entre 9 y 11', 'entre 5 y 6', 'más de 14'], 0, 'A esa edad el cuerpo y el cerebro necesitan entre 9 y 11 horas de sueño.'),
    BankQuestion(AgeBand.b9a11, 3, '¿Qué nutrientes dan energía rápida?', <String>['las vitaminas', 'los carbohidratos', 'el agua'], 1, 'Los carbohidratos (arroz, papa, pan, frutas) son la principal fuente de energía.'),
    BankQuestion(AgeBand.b9a11, 3, '¿Qué pasa con el ritmo del corazón cuando hacemos ejercicio a menudo?', <String>['se vuelve irregular', 'late más rápido en reposo', 'se fortalece y late más tranquilo en reposo'], 2, 'Un corazón entrenado bombea más sangre en cada latido y necesita latir menos veces en reposo.'),
    BankQuestion(AgeBand.b9a11, 4, '¿Por qué hay que lavarse las manos antes de comer?', <String>['para quitar microbios que pueden enfermarnos', 'para que la comida sepa mejor', 'para tener las manos frías'], 0, 'En las manos hay microbios que entran por la boca con la comida; el jabón los elimina.'),
    BankQuestion(AgeBand.b9a11, 4, '¿Qué hace una vacuna?', <String>['cura una enfermedad que ya tienes', 'enseña al cuerpo a defenderse antes de enfermar', 'reemplaza los glóbulos blancos'], 1, 'La vacuna muestra al cuerpo una versión inofensiva del microbio para que aprenda a defenderse.'),
    BankQuestion(AgeBand.b9a11, 4, '¿Qué parte del sistema nervioso lleva las órdenes del cerebro a los músculos?', <String>['las venas', 'los huesos', 'los nervios'], 2, 'Los nervios llevan señales eléctricas del cerebro a los músculos y de vuelta.'),
  ];
}
