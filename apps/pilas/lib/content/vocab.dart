import '../core/es.dart';

/// Vocabulario ilustrado con pictogramas de Twemoji. Cada palabra trae su
/// género y número, sus sílabas y etiquetas semánticas para clasificar.
///
/// Las etiquetas tienen familias separadas para que un criterio no se mezcle
/// con otro (la revisión completa está en docs/DECISIONES.md, anexo A):
/// - categoría: animal, comida, fruta, verdura, vehiculo, ropa, objeto,
///   juguete, escuela, cocina, bano, instrumento, cuerpo, planta, naturaleza;
/// - grupo de animal (uno o ninguno): mamifero, ave, pez, reptil, anfibio,
///   insecto;
/// - hábitat, la lista completa de dónde vive (si no está, no vive ahí):
///   hab:granja, hab:casa, hab:selva, hab:sabana, hab:bosque, hab:desierto,
///   hab:mar, hab:rio, hab:polo, hab:montana, hab:jardin;
/// - movimiento: mov:X si se mueve así de forma característica y no:X si
///   claramente no lo hace (lo dudoso no lleva ninguna de las dos, y queda
///   fuera de las preguntas de ese movimiento): vuela, nada, camina, salta,
///   repta, trepa;
/// - medio por el que va un vehículo: medio:tierra, medio:aire, medio:agua;
/// - uso de la ropa: uso:frio, uso:calor, uso:lluvia;
/// - familia de instrumento: inst:cuerdas, inst:viento, inst:percusion,
///   inst:teclado.
class VocabItem {
  const VocabItem(this.id, this.nombre, this.genero, this.silabas, this.emoji, this.tags, {this.plural = false});

  final String id;
  final String nombre;

  /// 'm' o 'f'.
  final String genero;

  /// Sustantivos que se usan en plural (uvas, tijeras, gafas de sol).
  final bool plural;
  final List<String> silabas;

  /// Código del archivo SVG de Twemoji.
  final String emoji;
  final List<String> tags;

  String get articulo => Es.articulo(genero, plural: plural, ante: nombre);

  String get articuloIndef => Es.articulo(genero, plural: plural, definido: false, ante: nombre);

  String get conArticulo => '$articulo $nombre';

  /// "al gato", "a la vaca", "a los guantes".
  String get aEl => Es.aEl(genero, nombre, plural: plural);

  /// "del libro", "de la casa".
  String get deEl => Es.deEl(genero, nombre, plural: plural);

  /// Elige la forma del verbo según el número: verbo('cuesta', 'cuestan').
  String verbo(String singular, String plural3) => plural ? plural3 : singular;

  /// Plural del nombre ("manzanas", "ratones"); los que ya son plurales no cambian.
  String get nombrePlural => plural ? nombre : Es.plural(nombre);

  bool has(String tag) => tags.contains(tag);

  bool get esAnimal => has('animal');

  /// Dónde vive (sin el prefijo hab:).
  Set<String> get habitats => <String>{for (final String t in tags) if (t.startsWith('hab:')) t.substring(4)};

  /// Lugares donde también vive alguna especie suya (el delfín rosado y el
  /// camarón de río, en Colombia): no se usan ni como respuesta ni como
  /// distractor de ese lugar, para no marcar mal a quien lo sabe.
  Set<String> get tambienVive => <String>{for (final String t in tags) if (t.startsWith('tambien:')) t.substring(8)};

  /// Grupo del animal (mamifero, ave...) o null.
  String? get grupo {
    for (final String g in Vocab.grupos) {
      if (has(g)) {
        return g;
      }
    }
    return null;
  }

  /// Si el animal se mueve así (true), si claramente no (false) o si es dudoso (null).
  bool? mueve(String movimiento) {
    if (has('mov:$movimiento')) {
      return true;
    }
    if (has('no:$movimiento')) {
      return false;
    }
    return null;
  }

  @override
  String toString() => nombre;
}

class Vocab {
  Vocab._();

  static const List<String> grupos = <String>['mamifero', 'ave', 'pez', 'reptil', 'anfibio', 'insecto'];
  static const List<String> movimientos = <String>['vuela', 'nada', 'camina', 'salta', 'repta', 'trepa'];
  static const List<String> habitatsTodos = <String>['granja', 'casa', 'selva', 'sabana', 'bosque', 'desierto', 'mar', 'rio', 'polo', 'montana', 'jardin'];

  static const List<VocabItem> all = <VocabItem>[
    // Animales de la granja y la casa
    VocabItem('gato', 'gato', 'm', <String>['ga', 'to'], '1f408', <String>['animal', 'mamifero', 'hab:casa', 'hab:granja', 'mov:camina', 'mov:trepa', 'no:vuela', 'no:repta']),
    VocabItem('perro', 'perro', 'm', <String>['pe', 'rro'], '1f415', <String>['animal', 'mamifero', 'hab:casa', 'hab:granja', 'mov:camina', 'no:vuela', 'no:repta', 'no:trepa']),
    VocabItem('vaca', 'vaca', 'f', <String>['va', 'ca'], '1f404', <String>['animal', 'mamifero', 'hab:granja', 'mov:camina', 'no:vuela', 'no:salta', 'no:repta', 'no:trepa']),
    VocabItem('cerdo', 'cerdo', 'm', <String>['cer', 'do'], '1f416', <String>['animal', 'mamifero', 'hab:granja', 'mov:camina', 'no:vuela', 'no:salta', 'no:repta', 'no:trepa']),
    VocabItem('gallina', 'gallina', 'f', <String>['ga', 'lli', 'na'], '1f414', <String>['animal', 'ave', 'hab:granja', 'mov:camina', 'no:nada', 'no:repta', 'no:trepa']),
    VocabItem('gallo', 'gallo', 'm', <String>['ga', 'llo'], '1f413', <String>['animal', 'ave', 'hab:granja', 'mov:camina', 'no:nada', 'no:repta', 'no:trepa']),
    VocabItem('pollito', 'pollito', 'm', <String>['po', 'lli', 'to'], '1f425', <String>['animal', 'ave', 'hab:granja', 'mov:camina', 'no:vuela', 'no:nada', 'no:repta', 'no:trepa']),
    VocabItem('oveja', 'oveja', 'f', <String>['o', 've', 'ja'], '1f411', <String>['animal', 'mamifero', 'hab:granja', 'mov:camina', 'no:vuela', 'no:repta', 'no:trepa']),
    VocabItem('cabra', 'cabra', 'f', <String>['ca', 'bra'], '1f410', <String>['animal', 'mamifero', 'hab:granja', 'hab:montana', 'mov:camina', 'mov:trepa', 'no:vuela', 'no:repta']),
    VocabItem('caballo', 'caballo', 'm', <String>['ca', 'ba', 'llo'], '1f40e', <String>['animal', 'mamifero', 'hab:granja', 'mov:camina', 'no:vuela', 'no:repta', 'no:trepa']),
    VocabItem('pato', 'pato', 'm', <String>['pa', 'to'], '1f986', <String>['animal', 'ave', 'hab:granja', 'hab:rio', 'mov:nada', 'mov:vuela', 'mov:camina', 'no:repta', 'no:trepa']),
    VocabItem('conejo', 'conejo', 'm', <String>['co', 'ne', 'jo'], '1f407', <String>['animal', 'mamifero', 'hab:granja', 'hab:casa', 'hab:bosque', 'mov:salta', 'no:vuela', 'no:repta', 'no:trepa']),
    VocabItem('raton', 'ratón', 'm', <String>['ra', 'tón'], '1f401', <String>['animal', 'mamifero', 'hab:casa', 'hab:granja', 'hab:bosque', 'mov:camina', 'mov:trepa', 'no:vuela']),
    VocabItem('burro', 'burro', 'm', <String>['bu', 'rro'], '1facf', <String>['animal', 'mamifero', 'hab:granja', 'mov:camina', 'no:vuela', 'no:repta', 'no:trepa']),
    VocabItem('pavo', 'pavo', 'm', <String>['pa', 'vo'], '1f983', <String>['animal', 'ave', 'hab:granja', 'mov:camina', 'no:nada', 'no:repta', 'no:trepa']),

    // Animales salvajes
    VocabItem('leon', 'león', 'm', <String>['le', 'ón'], '1f981', <String>['animal', 'mamifero', 'hab:sabana', 'mov:camina', 'no:vuela', 'no:repta']),
    VocabItem('tigre', 'tigre', 'm', <String>['ti', 'gre'], '1f405', <String>['animal', 'mamifero', 'hab:selva', 'hab:bosque', 'mov:camina', 'mov:nada', 'no:vuela', 'no:repta']),
    VocabItem('elefante', 'elefante', 'm', <String>['e', 'le', 'fan', 'te'], '1f418', <String>['animal', 'mamifero', 'hab:sabana', 'hab:selva', 'mov:camina', 'no:vuela', 'no:salta', 'no:repta', 'no:trepa']),
    VocabItem('jirafa', 'jirafa', 'f', <String>['ji', 'ra', 'fa'], '1f992', <String>['animal', 'mamifero', 'hab:sabana', 'mov:camina', 'no:vuela', 'no:repta', 'no:trepa']),
    VocabItem('mono', 'mono', 'm', <String>['mo', 'no'], '1f412', <String>['animal', 'mamifero', 'hab:selva', 'mov:trepa', 'no:vuela', 'no:repta']),
    VocabItem('cebra', 'cebra', 'f', <String>['ce', 'bra'], '1f993', <String>['animal', 'mamifero', 'hab:sabana', 'mov:camina', 'no:vuela', 'no:repta', 'no:trepa']),
    VocabItem('oso', 'oso', 'm', <String>['o', 'so'], '1f43b', <String>['animal', 'mamifero', 'hab:bosque', 'hab:montana', 'mov:camina', 'no:vuela', 'no:repta']),
    VocabItem('panda', 'panda', 'm', <String>['pan', 'da'], '1f43c', <String>['animal', 'mamifero', 'hab:bosque', 'hab:montana', 'mov:camina', 'mov:trepa', 'no:vuela', 'no:repta']),
    VocabItem('koala', 'koala', 'm', <String>['ko', 'a', 'la'], '1f428', <String>['animal', 'mamifero', 'hab:bosque', 'mov:trepa', 'no:vuela', 'no:repta']),
    VocabItem('zorro', 'zorro', 'm', <String>['zo', 'rro'], '1f98a', <String>['animal', 'mamifero', 'hab:bosque', 'mov:camina', 'no:vuela', 'no:repta']),
    VocabItem('lobo', 'lobo', 'm', <String>['lo', 'bo'], '1f43a', <String>['animal', 'mamifero', 'hab:bosque', 'hab:montana', 'mov:camina', 'no:vuela', 'no:repta', 'no:trepa']),
    VocabItem('venado', 'venado', 'm', <String>['ve', 'na', 'do'], '1f98c', <String>['animal', 'mamifero', 'hab:bosque', 'mov:camina', 'no:vuela', 'no:repta', 'no:trepa']),
    VocabItem('serpiente', 'serpiente', 'f', <String>['ser', 'pien', 'te'], '1f40d', <String>['animal', 'reptil', 'hab:selva', 'hab:desierto', 'hab:bosque', 'hab:sabana', 'hab:jardin', 'mov:repta', 'no:vuela', 'no:camina', 'no:salta']),
    VocabItem('tortuga', 'tortuga', 'f', <String>['tor', 'tu', 'ga'], '1f422', <String>['animal', 'reptil', 'hab:mar', 'hab:rio', 'mov:camina', 'mov:nada', 'no:vuela', 'no:salta', 'no:trepa']),
    VocabItem('lagartija', 'lagartija', 'f', <String>['la', 'gar', 'ti', 'ja'], '1f98e', <String>['animal', 'reptil', 'hab:desierto', 'hab:selva', 'hab:jardin', 'hab:bosque', 'mov:camina', 'mov:trepa', 'no:vuela']),
    VocabItem('cocodrilo', 'cocodrilo', 'm', <String>['co', 'co', 'dri', 'lo'], '1f40a', <String>['animal', 'reptil', 'hab:rio', 'mov:nada', 'mov:camina', 'no:vuela', 'no:trepa']),
    VocabItem('rana', 'rana', 'f', <String>['ra', 'na'], '1f438', <String>['animal', 'anfibio', 'hab:rio', 'hab:selva', 'mov:salta', 'mov:nada', 'no:vuela']),
    VocabItem('perezoso', 'perezoso', 'm', <String>['pe', 're', 'zo', 'so'], '1f9a5', <String>['animal', 'mamifero', 'hab:selva', 'mov:trepa', 'no:vuela', 'no:salta']),
    VocabItem('llama', 'llama', 'f', <String>['lla', 'ma'], '1f999', <String>['animal', 'mamifero', 'hab:montana', 'mov:camina', 'no:vuela', 'no:repta', 'no:trepa']),
    VocabItem('murcielago', 'murciélago', 'm', <String>['mur', 'cié', 'la', 'go'], '1f987', <String>['animal', 'mamifero', 'hab:selva', 'hab:bosque', 'mov:vuela', 'no:nada', 'no:repta']),
    VocabItem('canguro', 'canguro', 'm', <String>['can', 'gu', 'ro'], '1f998', <String>['animal', 'mamifero', 'mov:salta', 'no:vuela', 'no:repta', 'no:trepa']),
    VocabItem('hipopotamo', 'hipopótamo', 'm', <String>['hi', 'po', 'pó', 'ta', 'mo'], '1f99b', <String>['animal', 'mamifero', 'hab:rio', 'hab:sabana', 'mov:camina', 'no:vuela', 'no:salta', 'no:repta', 'no:trepa']),
    VocabItem('rinoceronte', 'rinoceronte', 'm', <String>['ri', 'no', 'ce', 'ron', 'te'], '1f98f', <String>['animal', 'mamifero', 'hab:sabana', 'mov:camina', 'no:vuela', 'no:salta', 'no:repta', 'no:trepa']),
    VocabItem('camello', 'camello', 'm', <String>['ca', 'me', 'llo'], '1f42b', <String>['animal', 'mamifero', 'hab:desierto', 'mov:camina', 'no:vuela', 'no:repta', 'no:trepa']),
    VocabItem('erizo', 'erizo', 'm', <String>['e', 'ri', 'zo'], '1f994', <String>['animal', 'mamifero', 'hab:bosque', 'hab:jardin', 'mov:camina', 'no:vuela']),
    VocabItem('nutria', 'nutria', 'f', <String>['nu', 'tria'], '1f9a6', <String>['animal', 'mamifero', 'hab:rio', 'mov:nada', 'no:vuela']),

    // Animales del agua
    VocabItem('pez', 'pez', 'm', <String>['pez'], '1f41f', <String>['animal', 'pez', 'hab:mar', 'hab:rio', 'mov:nada', 'no:vuela', 'no:camina', 'no:trepa']),
    VocabItem('delfin', 'delfín', 'm', <String>['del', 'fín'], '1f42c', <String>['animal', 'mamifero', 'hab:mar', 'tambien:rio', 'mov:nada', 'no:vuela', 'no:camina', 'no:trepa']),
    VocabItem('ballena', 'ballena', 'f', <String>['ba', 'lle', 'na'], '1f40b', <String>['animal', 'mamifero', 'hab:mar', 'mov:nada', 'no:vuela', 'no:camina', 'no:trepa']),
    VocabItem('tiburon', 'tiburón', 'm', <String>['ti', 'bu', 'rón'], '1f988', <String>['animal', 'pez', 'hab:mar', 'mov:nada', 'no:vuela', 'no:camina', 'no:salta', 'no:trepa']),
    VocabItem('pulpo', 'pulpo', 'm', <String>['pul', 'po'], '1f419', <String>['animal', 'hab:mar', 'mov:nada', 'no:vuela', 'no:salta']),
    VocabItem('cangrejo', 'cangrejo', 'm', <String>['can', 'gre', 'jo'], '1f980', <String>['animal', 'hab:mar', 'tambien:rio', 'mov:camina', 'no:vuela']),
    VocabItem('camaron', 'camarón', 'm', <String>['ca', 'ma', 'rón'], '1f990', <String>['animal', 'hab:mar', 'tambien:rio', 'mov:nada', 'no:vuela']),
    VocabItem('caracol', 'caracol', 'm', <String>['ca', 'ra', 'col'], '1f40c', <String>['animal', 'hab:jardin', 'mov:repta', 'no:vuela', 'no:nada', 'no:salta', 'no:camina']),
    VocabItem('foca', 'foca', 'f', <String>['fo', 'ca'], '1f9ad', <String>['animal', 'mamifero', 'hab:mar', 'hab:polo', 'mov:nada', 'no:vuela', 'no:trepa']),
    VocabItem('pinguino', 'pingüino', 'm', <String>['pin', 'güi', 'no'], '1f427', <String>['animal', 'ave', 'hab:mar', 'hab:polo', 'mov:nada', 'mov:camina', 'no:vuela', 'no:trepa']),

    // Aves e insectos
    VocabItem('aguila', 'águila', 'f', <String>['á', 'gui', 'la'], '1f985', <String>['animal', 'ave', 'hab:montana', 'hab:bosque', 'mov:vuela', 'no:nada', 'no:trepa']),
    VocabItem('buho', 'búho', 'm', <String>['bú', 'ho'], '1f989', <String>['animal', 'ave', 'hab:bosque', 'mov:vuela', 'no:nada']),
    VocabItem('loro', 'loro', 'm', <String>['lo', 'ro'], '1f99c', <String>['animal', 'ave', 'hab:selva', 'mov:vuela', 'mov:trepa', 'no:nada']),
    VocabItem('pajaro', 'pájaro', 'm', <String>['pá', 'ja', 'ro'], '1f426', <String>['animal', 'ave', 'hab:jardin', 'hab:bosque', 'mov:vuela', 'no:nada', 'no:repta']),
    VocabItem('flamenco', 'flamenco', 'm', <String>['fla', 'men', 'co'], '1f9a9', <String>['animal', 'ave', 'mov:vuela', 'mov:camina', 'no:repta', 'no:trepa']),
    VocabItem('pavoreal', 'pavo real', 'm', <String>['pa', 'vo', 're', 'al'], '1f99a', <String>['animal', 'ave', 'mov:camina', 'no:nada', 'no:repta']),
    VocabItem('mariposa', 'mariposa', 'f', <String>['ma', 'ri', 'po', 'sa'], '1f98b', <String>['animal', 'insecto', 'hab:jardin', 'hab:selva', 'mov:vuela', 'no:nada', 'no:repta']),
    VocabItem('abeja', 'abeja', 'f', <String>['a', 'be', 'ja'], '1f41d', <String>['animal', 'insecto', 'hab:jardin', 'mov:vuela', 'no:nada']),
    VocabItem('mariquita', 'mariquita', 'f', <String>['ma', 'ri', 'qui', 'ta'], '1f41e', <String>['animal', 'insecto', 'hab:jardin', 'mov:vuela', 'no:nada']),
    VocabItem('hormiga', 'hormiga', 'f', <String>['hor', 'mi', 'ga'], '1f41c', <String>['animal', 'insecto', 'hab:jardin', 'hab:selva', 'hab:bosque', 'mov:camina', 'no:repta']),
    VocabItem('arana', 'araña', 'f', <String>['a', 'ra', 'ña'], '1f577', <String>['animal', 'hab:casa', 'hab:jardin', 'mov:camina', 'mov:trepa', 'no:vuela']),
    VocabItem('unicornio', 'unicornio', 'm', <String>['u', 'ni', 'cor', 'nio'], '1f984', <String>['fantasia']),

    // Frutas
    VocabItem('manzana', 'manzana', 'f', <String>['man', 'za', 'na'], '1f34e', <String>['comida', 'fruta']),
    VocabItem('banano', 'banano', 'm', <String>['ba', 'na', 'no'], '1f34c', <String>['comida', 'fruta']),
    VocabItem('naranja', 'naranja', 'f', <String>['na', 'ran', 'ja'], '1f34a', <String>['comida', 'fruta']),
    VocabItem('uvas', 'uvas', 'f', <String>['u', 'vas'], '1f347', <String>['comida', 'fruta'], plural: true),
    VocabItem('fresa', 'fresa', 'f', <String>['fre', 'sa'], '1f353', <String>['comida', 'fruta']),
    VocabItem('sandia', 'sandía', 'f', <String>['san', 'dí', 'a'], '1f349', <String>['comida', 'fruta']),
    VocabItem('pina', 'piña', 'f', <String>['pi', 'ña'], '1f34d', <String>['comida', 'fruta']),
    VocabItem('mango', 'mango', 'm', <String>['man', 'go'], '1f96d', <String>['comida', 'fruta']),
    VocabItem('pera', 'pera', 'f', <String>['pe', 'ra'], '1f350', <String>['comida', 'fruta']),
    VocabItem('limon', 'limón', 'm', <String>['li', 'món'], '1f34b', <String>['comida', 'fruta']),
    // El pictograma trae dos cerezas: la palabra va en plural, como las uvas.
    VocabItem('cereza', 'cerezas', 'f', <String>['ce', 're', 'zas'], '1f352', <String>['comida', 'fruta'], plural: true),
    VocabItem('coco', 'coco', 'm', <String>['co', 'co'], '1f965', <String>['comida', 'fruta']),
    VocabItem('kiwi', 'kiwi', 'm', <String>['ki', 'wi'], '1f95d', <String>['comida', 'fruta']),
    VocabItem('durazno', 'durazno', 'm', <String>['du', 'raz', 'no'], '1f351', <String>['comida', 'fruta']),
    VocabItem('melon', 'melón', 'm', <String>['me', 'lón'], '1f348', <String>['comida', 'fruta']),

    // Verduras (solo las que en la cocina colombiana nadie discute; el tomate,
    // el aguacate, el ají, la papa y el maíz se dejan como "comida").
    VocabItem('zanahoria', 'zanahoria', 'f', <String>['za', 'na', 'ho', 'ria'], '1f955', <String>['comida', 'verdura']),
    VocabItem('maiz', 'maíz', 'm', <String>['ma', 'íz'], '1f33d', <String>['comida']),
    VocabItem('tomate', 'tomate', 'm', <String>['to', 'ma', 'te'], '1f345', <String>['comida']),
    VocabItem('papa', 'papa', 'f', <String>['pa', 'pa'], '1f954', <String>['comida']),
    VocabItem('cebolla', 'cebolla', 'f', <String>['ce', 'bo', 'lla'], '1f9c5', <String>['comida', 'verdura']),
    VocabItem('brocoli', 'brócoli', 'm', <String>['bró', 'co', 'li'], '1f966', <String>['comida', 'verdura']),
    VocabItem('lechuga', 'lechuga', 'f', <String>['le', 'chu', 'ga'], '1f96c', <String>['comida', 'verdura']),
    VocabItem('aji', 'ají', 'm', <String>['a', 'jí'], '1f336', <String>['comida']),
    VocabItem('aguacate', 'aguacate', 'm', <String>['a', 'gua', 'ca', 'te'], '1f951', <String>['comida']),
    VocabItem('berenjena', 'berenjena', 'f', <String>['be', 'ren', 'je', 'na'], '1f346', <String>['comida', 'verdura']),
    VocabItem('pepino', 'pepino', 'm', <String>['pe', 'pi', 'no'], '1f952', <String>['comida', 'verdura']),

    // Otras comidas
    VocabItem('pan', 'pan', 'm', <String>['pan'], '1f35e', <String>['comida']),
    VocabItem('queso', 'queso', 'm', <String>['que', 'so'], '1f9c0', <String>['comida']),
    VocabItem('huevo', 'huevo', 'm', <String>['hue', 'vo'], '1f95a', <String>['comida']),
    VocabItem('arroz', 'arroz', 'm', <String>['a', 'rroz'], '1f35a', <String>['comida']),
    VocabItem('pollo', 'pollo', 'm', <String>['po', 'llo'], '1f357', <String>['comida']),
    VocabItem('leche', 'leche', 'f', <String>['le', 'che'], '1f95b', <String>['comida', 'bebida']),
    VocabItem('helado', 'helado', 'm', <String>['he', 'la', 'do'], '1f366', <String>['comida', 'dulce']),
    VocabItem('galleta', 'galleta', 'f', <String>['ga', 'lle', 'ta'], '1f36a', <String>['comida', 'dulce']),
    VocabItem('torta', 'torta', 'f', <String>['tor', 'ta'], '1f382', <String>['comida', 'dulce']),
    VocabItem('pizza', 'pizza', 'f', <String>['pi', 'zza'], '1f355', <String>['comida']),
    VocabItem('chocolate', 'chocolate', 'm', <String>['cho', 'co', 'la', 'te'], '1f36b', <String>['comida', 'dulce']),
    VocabItem('miel', 'miel', 'f', <String>['miel'], '1f36f', <String>['comida', 'dulce']),
    VocabItem('jugo', 'jugo', 'm', <String>['ju', 'go'], '1f9c3', <String>['comida', 'bebida']),
    VocabItem('sopa', 'sopa', 'f', <String>['so', 'pa'], '1f963', <String>['comida']),
    VocabItem('arepa', 'arepa', 'f', <String>['a', 're', 'pa'], '1fad3', <String>['comida']),

    // Vehículos
    VocabItem('carro', 'carro', 'm', <String>['ca', 'rro'], '1f697', <String>['vehiculo', 'medio:tierra']),
    VocabItem('bus', 'bus', 'm', <String>['bus'], '1f68c', <String>['vehiculo', 'medio:tierra']),
    VocabItem('bicicleta', 'bicicleta', 'f', <String>['bi', 'ci', 'cle', 'ta'], '1f6b2', <String>['vehiculo', 'medio:tierra']),
    VocabItem('moto', 'moto', 'f', <String>['mo', 'to'], '1f3cd', <String>['vehiculo', 'medio:tierra']),
    VocabItem('tren', 'tren', 'm', <String>['tren'], '1f682', <String>['vehiculo', 'medio:tierra']),
    VocabItem('helicoptero', 'helicóptero', 'm', <String>['he', 'li', 'cóp', 'te', 'ro'], '1f681', <String>['vehiculo', 'medio:aire']),
    VocabItem('avion', 'avión', 'm', <String>['a', 'vión'], '2708', <String>['vehiculo', 'medio:aire']),
    VocabItem('cohete', 'cohete', 'm', <String>['co', 'he', 'te'], '1f680', <String>['vehiculo', 'medio:aire']),
    VocabItem('velero', 'velero', 'm', <String>['ve', 'le', 'ro'], '26f5', <String>['vehiculo', 'medio:agua']),
    VocabItem('barco', 'barco', 'm', <String>['bar', 'co'], '1f6a2', <String>['vehiculo', 'medio:agua']),
    VocabItem('bomberos', 'carro de bomberos', 'm', <String>['ca', 'rro', 'de', 'bom', 'be', 'ros'], '1f692', <String>['vehiculo', 'medio:tierra']),
    VocabItem('ambulancia', 'ambulancia', 'f', <String>['am', 'bu', 'lan', 'cia'], '1f691', <String>['vehiculo', 'medio:tierra']),
    VocabItem('tractor', 'tractor', 'm', <String>['trac', 'tor'], '1f69c', <String>['vehiculo', 'medio:tierra']),
    VocabItem('patineta', 'patineta', 'f', <String>['pa', 'ti', 'ne', 'ta'], '1f6f9', <String>['vehiculo', 'medio:tierra', 'juguete']),
    VocabItem('camion', 'camión', 'm', <String>['ca', 'mión'], '1f69a', <String>['vehiculo', 'medio:tierra']),

    // Ropa y calzado
    VocabItem('camiseta', 'camiseta', 'f', <String>['ca', 'mi', 'se', 'ta'], '1f455', <String>['ropa', 'uso:calor']),
    VocabItem('uniforme', 'uniforme', 'm', <String>['u', 'ni', 'for', 'me'], '1f94b', <String>['ropa']),
    VocabItem('pantalon', 'pantalón', 'm', <String>['pan', 'ta', 'lón'], '1f456', <String>['ropa']),
    VocabItem('vestido', 'vestido', 'm', <String>['ves', 'ti', 'do'], '1f457', <String>['ropa']),
    VocabItem('zapato', 'zapato', 'm', <String>['za', 'pa', 'to'], '1f45e', <String>['ropa']),
    VocabItem('tenis', 'tenis', 'm', <String>['te', 'nis'], '1f45f', <String>['ropa'], plural: true),
    VocabItem('gorra', 'gorra', 'f', <String>['go', 'rra'], '1f9e2', <String>['ropa', 'uso:calor']),
    VocabItem('medias', 'medias', 'f', <String>['me', 'dias'], '1f9e6', <String>['ropa'], plural: true),
    VocabItem('guantes', 'guantes', 'm', <String>['guan', 'tes'], '1f9e4', <String>['ropa', 'uso:frio'], plural: true),
    VocabItem('bufanda', 'bufanda', 'f', <String>['bu', 'fan', 'da'], '1f9e3', <String>['ropa', 'uso:frio']),
    VocabItem('sombrero', 'sombrero', 'm', <String>['som', 'bre', 'ro'], '1f452', <String>['ropa', 'uso:calor']),
    VocabItem('botas', 'botas', 'f', <String>['bo', 'tas'], '1f97e', <String>['ropa', 'uso:lluvia'], plural: true),
    VocabItem('gafas', 'gafas de sol', 'f', <String>['ga', 'fas', 'de', 'sol'], '1f576', <String>['ropa', 'uso:calor'], plural: true),
    VocabItem('chaqueta', 'chaqueta', 'f', <String>['cha', 'que', 'ta'], '1f9e5', <String>['ropa', 'uso:frio']),

    // Cuerpo
    VocabItem('oreja', 'oreja', 'f', <String>['o', 're', 'ja'], '1f442', <String>['cuerpo']),
    VocabItem('nariz', 'nariz', 'f', <String>['na', 'riz'], '1f443', <String>['cuerpo']),
    // El dibujo muestra varias uñas pintadas: la palabra va en plural.
    VocabItem('unas', 'uñas', 'f', <String>['u', 'ñas'], '1f485', <String>['cuerpo'], plural: true),
    VocabItem('ojo', 'ojo', 'm', <String>['o', 'jo'], '1f441', <String>['cuerpo']),
    VocabItem('boca', 'boca', 'f', <String>['bo', 'ca'], '1f444', <String>['cuerpo']),
    VocabItem('lengua', 'lengua', 'f', <String>['len', 'gua'], '1f445', <String>['cuerpo']),
    VocabItem('diente', 'diente', 'm', <String>['dien', 'te'], '1f9b7', <String>['cuerpo']),
    VocabItem('mano', 'mano', 'f', <String>['ma', 'no'], '1f590', <String>['cuerpo']),
    VocabItem('pie', 'pie', 'm', <String>['pie'], '1f9b6', <String>['cuerpo']),
    VocabItem('pierna', 'pierna', 'f', <String>['pier', 'na'], '1f9b5', <String>['cuerpo']),
    VocabItem('brazo', 'brazo', 'm', <String>['bra', 'zo'], '1f4aa', <String>['cuerpo']),
    VocabItem('cerebro', 'cerebro', 'm', <String>['ce', 're', 'bro'], '1f9e0', <String>['cuerpo', 'organo']),
    VocabItem('corazon', 'corazón', 'm', <String>['co', 'ra', 'zón'], '1fac0', <String>['cuerpo', 'organo']),
    VocabItem('pulmones', 'pulmones', 'm', <String>['pul', 'mo', 'nes'], '1fac1', <String>['cuerpo', 'organo'], plural: true),
    VocabItem('hueso', 'hueso', 'm', <String>['hue', 'so'], '1f9b4', <String>['cuerpo']),

    // Casa, escuela y objetos
    VocabItem('casa', 'casa', 'f', <String>['ca', 'sa'], '1f3e0', <String>['lugar']),
    VocabItem('puerta', 'puerta', 'f', <String>['puer', 'ta'], '1f6aa', <String>['objeto', 'hogar']),
    VocabItem('silla', 'silla', 'f', <String>['si', 'lla'], '1fa91', <String>['objeto', 'hogar', 'mueble']),
    VocabItem('cama', 'cama', 'f', <String>['ca', 'ma'], '1f6cf', <String>['objeto', 'hogar', 'mueble']),
    VocabItem('sofa', 'sofá', 'm', <String>['so', 'fá'], '1f6cb', <String>['objeto', 'hogar', 'mueble']),
    VocabItem('ventana', 'ventana', 'f', <String>['ven', 'ta', 'na'], '1fa9f', <String>['objeto', 'hogar']),
    VocabItem('llave', 'llave', 'f', <String>['lla', 've'], '1f511', <String>['objeto', 'hogar']),
    VocabItem('reloj', 'reloj', 'm', <String>['re', 'loj'], '23f0', <String>['objeto', 'hogar']),
    VocabItem('bombillo', 'bombillo', 'm', <String>['bom', 'bi', 'llo'], '1f4a1', <String>['objeto', 'hogar']),
    VocabItem('libros', 'libros', 'm', <String>['li', 'bros'], '1f4da', <String>['objeto', 'escuela'], plural: true),
    VocabItem('lapiz', 'lápiz', 'm', <String>['lá', 'piz'], '270f', <String>['objeto', 'escuela']),
    VocabItem('regla', 'regla', 'f', <String>['re', 'gla'], '1f4cf', <String>['objeto', 'escuela']),
    VocabItem('tijeras', 'tijeras', 'f', <String>['ti', 'je', 'ras'], '2702', <String>['objeto', 'escuela'], plural: true),
    VocabItem('crayon', 'crayón', 'm', <String>['cra', 'yón'], '1f58d', <String>['objeto', 'escuela']),
    VocabItem('libro', 'libro', 'm', <String>['li', 'bro'], '1f4d6', <String>['objeto', 'escuela']),
    VocabItem('pincel', 'pincel', 'm', <String>['pin', 'cel'], '1f58c', <String>['objeto', 'escuela']),
    VocabItem('maleta', 'maleta', 'f', <String>['ma', 'le', 'ta'], '1f392', <String>['objeto', 'escuela']),
    VocabItem('balon', 'balón', 'm', <String>['ba', 'lón'], '26bd', <String>['objeto', 'juguete']),
    VocabItem('oso_peluche', 'oso de peluche', 'm', <String>['o', 'so', 'de', 'pe', 'lu', 'che'], '1f9f8', <String>['objeto', 'juguete']),
    VocabItem('cometa', 'cometa', 'f', <String>['co', 'me', 'ta'], '1fa81', <String>['objeto', 'juguete']),
    VocabItem('globo', 'globo', 'm', <String>['glo', 'bo'], '1f388', <String>['objeto', 'juguete']),
    VocabItem('rompecabezas', 'rompecabezas', 'm', <String>['rom', 'pe', 'ca', 'be', 'zas'], '1f9e9', <String>['objeto', 'juguete']),
    VocabItem('dado', 'dado', 'm', <String>['da', 'do'], '1f3b2', <String>['objeto', 'juguete']),
    VocabItem('yoyo', 'yoyó', 'm', <String>['yo', 'yó'], '1fa80', <String>['objeto', 'juguete']),
    VocabItem('cepillo', 'cepillo de dientes', 'm', <String>['ce', 'pi', 'llo', 'de', 'dien', 'tes'], '1faa5', <String>['objeto', 'bano']),
    VocabItem('jabon', 'jabón', 'm', <String>['ja', 'bón'], '1f9fc', <String>['objeto', 'bano']),
    VocabItem('banera', 'bañera', 'f', <String>['ba', 'ñe', 'ra'], '1f6c1', <String>['objeto', 'bano']),
    VocabItem('balde', 'balde', 'm', <String>['bal', 'de'], '1faa3', <String>['objeto', 'hogar']),
    VocabItem('escoba', 'escoba', 'f', <String>['es', 'co', 'ba'], '1f9f9', <String>['objeto', 'hogar']),
    VocabItem('plato', 'plato', 'm', <String>['pla', 'to'], '1f37d', <String>['objeto', 'cocina']),
    VocabItem('cuchara', 'cuchara', 'f', <String>['cu', 'cha', 'ra'], '1f944', <String>['objeto', 'cocina']),
    VocabItem('tenedor', 'tenedor', 'm', <String>['te', 'ne', 'dor'], '1f374', <String>['objeto', 'cocina']),
    VocabItem('olla', 'olla', 'f', <String>['o', 'lla'], '1f372', <String>['objeto', 'cocina']),
    VocabItem('tetera', 'tetera', 'f', <String>['te', 'te', 'ra'], '1fad6', <String>['objeto', 'cocina']),
    VocabItem('telefono', 'teléfono', 'm', <String>['te', 'lé', 'fo', 'no'], '1f4f1', <String>['objeto', 'hogar', 'pantalla']),
    VocabItem('computador', 'computador', 'm', <String>['com', 'pu', 'ta', 'dor'], '1f4bb', <String>['objeto', 'hogar', 'pantalla']),
    VocabItem('televisor', 'televisor', 'm', <String>['te', 'le', 'vi', 'sor'], '1f4fa', <String>['objeto', 'hogar', 'pantalla']),
    VocabItem('camara', 'cámara', 'f', <String>['cá', 'ma', 'ra'], '1f4f7', <String>['objeto', 'hogar']),
    VocabItem('iman', 'imán', 'm', <String>['i', 'mán'], '1f9f2', <String>['objeto']),

    // Instrumentos
    VocabItem('guitarra', 'guitarra', 'f', <String>['gui', 'ta', 'rra'], '1f3b8', <String>['objeto', 'instrumento', 'inst:cuerdas']),
    VocabItem('tambor', 'tambor', 'm', <String>['tam', 'bor'], '1fa98', <String>['objeto', 'instrumento', 'inst:percusion']),
    VocabItem('trompeta', 'trompeta', 'f', <String>['trom', 'pe', 'ta'], '1f3ba', <String>['objeto', 'instrumento', 'inst:viento']),
    VocabItem('violin', 'violín', 'm', <String>['vio', 'lín'], '1f3bb', <String>['objeto', 'instrumento', 'inst:cuerdas']),
    VocabItem('piano', 'piano', 'm', <String>['pia', 'no'], '1f3b9', <String>['objeto', 'instrumento', 'inst:teclado']),
    VocabItem('acordeon', 'acordeón', 'm', <String>['a', 'cor', 'de', 'ón'], '1fa97', <String>['objeto', 'instrumento', 'inst:viento']),
    VocabItem('maracas', 'maracas', 'f', <String>['ma', 'ra', 'cas'], '1fa87', <String>['objeto', 'instrumento', 'inst:percusion'], plural: true),
    VocabItem('flauta', 'flauta', 'f', <String>['flau', 'ta'], '1fa88', <String>['objeto', 'instrumento', 'inst:viento']),

    // Naturaleza y clima
    VocabItem('sol', 'sol', 'm', <String>['sol'], '2600', <String>['naturaleza', 'cielo']),
    VocabItem('luna', 'luna', 'f', <String>['lu', 'na'], '1f319', <String>['naturaleza', 'cielo']),
    VocabItem('estrella', 'estrella', 'f', <String>['es', 'tre', 'lla'], '2b50', <String>['naturaleza', 'cielo']),
    VocabItem('nube', 'nube', 'f', <String>['nu', 'be'], '2601', <String>['naturaleza', 'cielo']),
    VocabItem('lluvia', 'lluvia', 'f', <String>['llu', 'via'], '1f327', <String>['naturaleza', 'clima']),
    VocabItem('tormenta', 'tormenta', 'f', <String>['tor', 'men', 'ta'], '26c8', <String>['naturaleza', 'clima']),
    VocabItem('arcoiris', 'arcoíris', 'm', <String>['ar', 'co', 'í', 'ris'], '1f308', <String>['naturaleza', 'cielo']),
    VocabItem('nieve', 'nieve', 'f', <String>['nie', 've'], '2744', <String>['naturaleza', 'clima']),
    VocabItem('ola', 'ola', 'f', <String>['o', 'la'], '1f30a', <String>['naturaleza']),
    VocabItem('fuego', 'fuego', 'm', <String>['fue', 'go'], '1f525', <String>['naturaleza']),
    VocabItem('arbol', 'árbol', 'm', <String>['ár', 'bol'], '1f333', <String>['naturaleza', 'planta']),
    VocabItem('pino', 'pino', 'm', <String>['pi', 'no'], '1f332', <String>['naturaleza', 'planta']),
    VocabItem('palmera', 'palmera', 'f', <String>['pal', 'me', 'ra'], '1f334', <String>['naturaleza', 'planta']),
    VocabItem('cactus', 'cactus', 'm', <String>['cac', 'tus'], '1f335', <String>['naturaleza', 'planta']),
    VocabItem('flor', 'flor', 'f', <String>['flor'], '1f338', <String>['naturaleza', 'planta']),
    VocabItem('girasol', 'girasol', 'm', <String>['gi', 'ra', 'sol'], '1f33b', <String>['naturaleza', 'planta']),
    VocabItem('rosa', 'rosa', 'f', <String>['ro', 'sa'], '1f339', <String>['naturaleza', 'planta']),
    VocabItem('tulipan', 'tulipán', 'm', <String>['tu', 'li', 'pán'], '1f337', <String>['naturaleza', 'planta']),
    VocabItem('hongo', 'hongo', 'm', <String>['hon', 'go'], '1f344', <String>['naturaleza']),
    VocabItem('trebol', 'trébol', 'm', <String>['tré', 'bol'], '1f340', <String>['naturaleza', 'planta']),
    VocabItem('hoja', 'hoja', 'f', <String>['ho', 'ja'], '1f343', <String>['naturaleza']),
    VocabItem('piedra', 'piedra', 'f', <String>['pie', 'dra'], '1faa8', <String>['naturaleza']),
    VocabItem('montana', 'montaña', 'f', <String>['mon', 'ta', 'ña'], '26f0', <String>['naturaleza', 'lugar']),
    VocabItem('volcan', 'volcán', 'm', <String>['vol', 'cán'], '1f30b', <String>['naturaleza', 'lugar']),
    VocabItem('isla', 'isla', 'f', <String>['is', 'la'], '1f3dd', <String>['naturaleza', 'lugar']),
    VocabItem('tierra', 'planeta Tierra', 'm', <String>['pla', 'ne', 'ta', 'tie', 'rra'], '1f30d', <String>['naturaleza']),
  ];

  /// Pictogramas que muestran exactamente un objeto entero, revisados uno
  /// por uno rasterizando el SVG. Solo estos se usan cuando un juego dibuja
  /// varias copias para que el niño cuente cuántas hay. Quedan fuera, entre
  /// otros: las cerezas (el dibujo trae dos), las uvas (un racimo), la
  /// sandía y la pizza (una tajada), el coco, el kiwi y el aguacate
  /// (partidos), el pollo (una presa), el queso (un pedazo), la lechuga
  /// (hojas sueltas), el melón (se confunde con un repollo), el rompecabezas
  /// (una ficha) y los libros (una pila). test/content_test.dart compara la
  /// lista con lo que dibujan las rondas de contar.
  static const Set<String> unObjeto = <String>{
    // Frutas.
    'manzana', 'banano', 'naranja', 'fresa', 'pina', 'mango', 'pera', 'limon', 'durazno',
    // Verduras.
    'zanahoria', 'maiz', 'tomate', 'papa', 'cebolla', 'brocoli', 'aji', 'berenjena', 'pepino',
    // Otras comidas.
    'pan', 'huevo', 'helado', 'galleta', 'torta', 'chocolate', 'arepa',
    // Escuela y juguetes.
    'lapiz', 'regla', 'crayon', 'libro', 'pincel', 'maleta', 'balon', 'cometa', 'globo', 'dado', 'yoyo', 'patineta',
  };

  /// Las palabras cuyo pictograma se puede contar (ver [unObjeto]).
  static List<VocabItem> get contables => all.where((VocabItem v) => unObjeto.contains(v.id)).toList();

  static VocabItem? byId(String id) {
    for (final VocabItem v in all) {
      if (v.id == id) {
        return v;
      }
    }
    return null;
  }

  static VocabItem item(String id) => byId(id)!;

  static List<VocabItem> withTag(String tag) => all.where((VocabItem v) => v.has(tag)).toList();

  static List<VocabItem> withAllTags(List<String> tags) => all.where((VocabItem v) => tags.every((String t) => v.has(t))).toList();

  static List<VocabItem> withoutTag(String tag) => all.where((VocabItem v) => !v.has(tag)).toList();

  /// Palabras sueltas (sin espacios) con [n] sílabas, para contar sílabas.
  static List<VocabItem> withSyllables(int n) => all.where((VocabItem v) => v.silabas.length == n && !v.nombre.contains(' ')).toList();
}
