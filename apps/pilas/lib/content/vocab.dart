/// Vocabulario ilustrado con pictogramas de Twemoji. Cada palabra trae su
/// género, sus sílabas y etiquetas para clasificar.
class VocabItem {
  const VocabItem(this.id, this.nombre, this.genero, this.silabas, this.emoji, this.tags);

  final String id;
  final String nombre;

  /// 'm' o 'f'.
  final String genero;
  final List<String> silabas;

  /// Código del archivo SVG de Twemoji.
  final String emoji;
  final List<String> tags;

  String get articulo => genero == 'f' ? 'la' : 'el';

  String get conArticulo => '$articulo $nombre';

  String get articuloIndef => genero == 'f' ? 'una' : 'un';

  /// Primera letra (sonido inicial).
  String get inicial => nombre.substring(0, 1);

  bool has(String tag) => tags.contains(tag);

  bool get esAnimal => has('animal');

  @override
  String toString() => nombre;
}

class Vocab {
  Vocab._();

  static const List<VocabItem> all = <VocabItem>[
    // Animales de la granja y la casa
    VocabItem('gato', 'gato', 'm', <String>['ga', 'to'], '1f408', <String>['animal', 'casa', 'mamifero', 'camina', 'tierra']),
    VocabItem('perro', 'perro', 'm', <String>['pe', 'rro'], '1f415', <String>['animal', 'casa', 'mamifero', 'camina', 'tierra']),
    VocabItem('vaca', 'vaca', 'f', <String>['va', 'ca'], '1f404', <String>['animal', 'granja', 'mamifero', 'camina', 'tierra', 'leche']),
    VocabItem('cerdo', 'cerdo', 'm', <String>['cer', 'do'], '1f416', <String>['animal', 'granja', 'mamifero', 'camina', 'tierra']),
    VocabItem('gallina', 'gallina', 'f', <String>['ga', 'lli', 'na'], '1f414', <String>['animal', 'granja', 'ave', 'camina', 'tierra', 'huevo']),
    VocabItem('gallo', 'gallo', 'm', <String>['ga', 'llo'], '1f413', <String>['animal', 'granja', 'ave', 'camina', 'tierra']),
    VocabItem('pollito', 'pollito', 'm', <String>['po', 'lli', 'to'], '1f423', <String>['animal', 'granja', 'ave', 'cria', 'tierra']),
    VocabItem('oveja', 'oveja', 'f', <String>['o', 've', 'ja'], '1f411', <String>['animal', 'granja', 'mamifero', 'camina', 'tierra', 'lana']),
    VocabItem('cabra', 'cabra', 'f', <String>['ca', 'bra'], '1f410', <String>['animal', 'granja', 'mamifero', 'camina', 'tierra']),
    VocabItem('caballo', 'caballo', 'm', <String>['ca', 'ba', 'llo'], '1f40e', <String>['animal', 'granja', 'mamifero', 'camina', 'tierra']),
    VocabItem('pato', 'pato', 'm', <String>['pa', 'to'], '1f986', <String>['animal', 'granja', 'ave', 'nada', 'vuela', 'agua']),
    VocabItem('conejo', 'conejo', 'm', <String>['co', 'ne', 'jo'], '1f407', <String>['animal', 'granja', 'mamifero', 'camina', 'tierra']),
    VocabItem('raton', 'ratón', 'm', <String>['ra', 'tón'], '1f401', <String>['animal', 'casa', 'mamifero', 'camina', 'tierra']),
    VocabItem('burro', 'burro', 'm', <String>['bu', 'rro'], '1facf', <String>['animal', 'granja', 'mamifero', 'camina', 'tierra']),
    VocabItem('pavo', 'pavo', 'm', <String>['pa', 'vo'], '1f983', <String>['animal', 'granja', 'ave', 'camina', 'tierra']),

    // Animales de la selva y el bosque
    VocabItem('leon', 'león', 'm', <String>['le', 'ón'], '1f981', <String>['animal', 'selva', 'mamifero', 'camina', 'tierra', 'salvaje']),
    VocabItem('tigre', 'tigre', 'm', <String>['ti', 'gre'], '1f405', <String>['animal', 'selva', 'mamifero', 'camina', 'tierra', 'salvaje']),
    VocabItem('elefante', 'elefante', 'm', <String>['e', 'le', 'fan', 'te'], '1f418', <String>['animal', 'selva', 'mamifero', 'camina', 'tierra', 'salvaje', 'grande']),
    VocabItem('jirafa', 'jirafa', 'f', <String>['ji', 'ra', 'fa'], '1f992', <String>['animal', 'selva', 'mamifero', 'camina', 'tierra', 'salvaje', 'grande']),
    VocabItem('mono', 'mono', 'm', <String>['mo', 'no'], '1f412', <String>['animal', 'selva', 'mamifero', 'trepa', 'tierra', 'salvaje', 'colombia']),
    VocabItem('cebra', 'cebra', 'f', <String>['ce', 'bra'], '1f993', <String>['animal', 'selva', 'mamifero', 'camina', 'tierra', 'salvaje']),
    VocabItem('oso', 'oso', 'm', <String>['o', 'so'], '1f43b', <String>['animal', 'bosque', 'mamifero', 'camina', 'tierra', 'salvaje', 'colombia']),
    VocabItem('panda', 'panda', 'm', <String>['pan', 'da'], '1f43c', <String>['animal', 'bosque', 'mamifero', 'camina', 'tierra', 'salvaje']),
    VocabItem('koala', 'koala', 'm', <String>['ko', 'a', 'la'], '1f428', <String>['animal', 'bosque', 'mamifero', 'trepa', 'tierra', 'salvaje']),
    VocabItem('zorro', 'zorro', 'm', <String>['zo', 'rro'], '1f98a', <String>['animal', 'bosque', 'mamifero', 'camina', 'tierra', 'salvaje']),
    VocabItem('lobo', 'lobo', 'm', <String>['lo', 'bo'], '1f43a', <String>['animal', 'bosque', 'mamifero', 'camina', 'tierra', 'salvaje']),
    VocabItem('venado', 'venado', 'm', <String>['ve', 'na', 'do'], '1f98c', <String>['animal', 'bosque', 'mamifero', 'camina', 'tierra', 'salvaje', 'colombia']),
    VocabItem('serpiente', 'serpiente', 'f', <String>['ser', 'pien', 'te'], '1f40d', <String>['animal', 'selva', 'reptil', 'repta', 'tierra', 'salvaje', 'colombia']),
    VocabItem('tortuga', 'tortuga', 'f', <String>['tor', 'tu', 'ga'], '1f422', <String>['animal', 'reptil', 'camina', 'nada', 'agua', 'tierra', 'colombia', 'lenta']),
    VocabItem('lagartija', 'lagartija', 'f', <String>['la', 'gar', 'ti', 'ja'], '1f98e', <String>['animal', 'reptil', 'camina', 'tierra', 'salvaje']),
    VocabItem('cocodrilo', 'cocodrilo', 'm', <String>['co', 'co', 'dri', 'lo'], '1f40a', <String>['animal', 'rio', 'reptil', 'nada', 'agua', 'salvaje', 'colombia']),
    VocabItem('rana', 'rana', 'f', <String>['ra', 'na'], '1f438', <String>['animal', 'rio', 'anfibio', 'salta', 'agua', 'colombia']),
    VocabItem('perezoso', 'perezoso', 'm', <String>['pe', 're', 'zo', 'so'], '1f9a5', <String>['animal', 'selva', 'mamifero', 'trepa', 'tierra', 'colombia', 'lento']),
    VocabItem('llama', 'llama', 'f', <String>['lla', 'ma'], '1f999', <String>['animal', 'montana', 'mamifero', 'camina', 'tierra', 'andes']),
    VocabItem('murcielago', 'murciélago', 'm', <String>['mur', 'cié', 'la', 'go'], '1f987', <String>['animal', 'bosque', 'mamifero', 'vuela', 'aire', 'noche']),
    VocabItem('canguro', 'canguro', 'm', <String>['can', 'gu', 'ro'], '1f998', <String>['animal', 'salvaje', 'mamifero', 'salta', 'tierra']),
    VocabItem('hipopotamo', 'hipopótamo', 'm', <String>['hi', 'po', 'pó', 'ta', 'mo'], '1f99b', <String>['animal', 'rio', 'mamifero', 'nada', 'agua', 'salvaje', 'grande']),
    VocabItem('rinoceronte', 'rinoceronte', 'm', <String>['ri', 'no', 'ce', 'ron', 'te'], '1f98f', <String>['animal', 'selva', 'mamifero', 'camina', 'tierra', 'salvaje', 'grande']),
    VocabItem('camello', 'camello', 'm', <String>['ca', 'me', 'llo'], '1f42b', <String>['animal', 'desierto', 'mamifero', 'camina', 'tierra']),
    VocabItem('erizo', 'erizo', 'm', <String>['e', 'ri', 'zo'], '1f994', <String>['animal', 'bosque', 'mamifero', 'camina', 'tierra']),
    VocabItem('nutria', 'nutria', 'f', <String>['nu', 'tria'], '1f9a6', <String>['animal', 'rio', 'mamifero', 'nada', 'agua', 'colombia']),

    // Animales del agua
    VocabItem('pez', 'pez', 'm', <String>['pez'], '1f41f', <String>['animal', 'mar', 'pez', 'nada', 'agua']),
    VocabItem('delfin', 'delfín', 'm', <String>['del', 'fín'], '1f42c', <String>['animal', 'mar', 'mamifero', 'nada', 'agua', 'colombia']),
    VocabItem('ballena', 'ballena', 'f', <String>['ba', 'lle', 'na'], '1f40b', <String>['animal', 'mar', 'mamifero', 'nada', 'agua', 'grande', 'colombia']),
    VocabItem('tiburon', 'tiburón', 'm', <String>['ti', 'bu', 'rón'], '1f988', <String>['animal', 'mar', 'pez', 'nada', 'agua']),
    VocabItem('pulpo', 'pulpo', 'm', <String>['pul', 'po'], '1f419', <String>['animal', 'mar', 'nada', 'agua']),
    VocabItem('cangrejo', 'cangrejo', 'm', <String>['can', 'gre', 'jo'], '1f980', <String>['animal', 'mar', 'camina', 'agua', 'playa']),
    VocabItem('camaron', 'camarón', 'm', <String>['ca', 'ma', 'rón'], '1f990', <String>['animal', 'mar', 'nada', 'agua']),
    VocabItem('caracol', 'caracol', 'm', <String>['ca', 'ra', 'col'], '1f40c', <String>['animal', 'jardin', 'repta', 'tierra', 'lento']),
    VocabItem('foca', 'foca', 'f', <String>['fo', 'ca'], '1f9ad', <String>['animal', 'mar', 'mamifero', 'nada', 'agua', 'frio']),
    VocabItem('pinguino', 'pingüino', 'm', <String>['pin', 'güi', 'no'], '1f427', <String>['animal', 'mar', 'ave', 'nada', 'agua', 'frio']),

    // Aves e insectos
    VocabItem('aguila', 'águila', 'f', <String>['á', 'gui', 'la'], '1f985', <String>['animal', 'montana', 'ave', 'vuela', 'aire', 'colombia']),
    VocabItem('buho', 'búho', 'm', <String>['bú', 'ho'], '1f989', <String>['animal', 'bosque', 'ave', 'vuela', 'aire', 'noche']),
    VocabItem('loro', 'loro', 'm', <String>['lo', 'ro'], '1f99c', <String>['animal', 'selva', 'ave', 'vuela', 'aire', 'colombia']),
    VocabItem('pajaro', 'pájaro', 'm', <String>['pá', 'ja', 'ro'], '1f426', <String>['animal', 'jardin', 'ave', 'vuela', 'aire']),
    VocabItem('flamenco', 'flamenco', 'm', <String>['fla', 'men', 'co'], '1f9a9', <String>['animal', 'rio', 'ave', 'vuela', 'aire', 'agua', 'colombia']),
    VocabItem('pavoreal', 'pavo real', 'm', <String>['pa', 'vo', 're', 'al'], '1f99a', <String>['animal', 'ave', 'camina', 'tierra']),
    VocabItem('mariposa', 'mariposa', 'f', <String>['ma', 'ri', 'po', 'sa'], '1f98b', <String>['animal', 'jardin', 'insecto', 'vuela', 'aire', 'colombia']),
    VocabItem('abeja', 'abeja', 'f', <String>['a', 'be', 'ja'], '1f41d', <String>['animal', 'jardin', 'insecto', 'vuela', 'aire', 'miel']),
    VocabItem('mariquita', 'mariquita', 'f', <String>['ma', 'ri', 'qui', 'ta'], '1f41e', <String>['animal', 'jardin', 'insecto', 'vuela', 'aire']),
    VocabItem('hormiga', 'hormiga', 'f', <String>['hor', 'mi', 'ga'], '1f41c', <String>['animal', 'jardin', 'insecto', 'camina', 'tierra', 'pequena']),
    VocabItem('arana', 'araña', 'f', <String>['a', 'ra', 'ña'], '1f577', <String>['animal', 'casa', 'camina', 'tierra', 'pequena']),

    // Frutas
    VocabItem('manzana', 'manzana', 'f', <String>['man', 'za', 'na'], '1f34e', <String>['comida', 'fruta', 'rojo', 'arbol']),
    VocabItem('banano', 'banano', 'm', <String>['ba', 'na', 'no'], '1f34c', <String>['comida', 'fruta', 'amarillo', 'colombia']),
    VocabItem('naranja', 'naranja', 'f', <String>['na', 'ran', 'ja'], '1f34a', <String>['comida', 'fruta', 'naranja', 'arbol']),
    VocabItem('uvas', 'uvas', 'f', <String>['u', 'vas'], '1f347', <String>['comida', 'fruta', 'morado', 'plural']),
    VocabItem('fresa', 'fresa', 'f', <String>['fre', 'sa'], '1f353', <String>['comida', 'fruta', 'rojo']),
    VocabItem('sandia', 'sandía', 'f', <String>['san', 'dí', 'a'], '1f349', <String>['comida', 'fruta', 'verde', 'grande']),
    VocabItem('pina', 'piña', 'f', <String>['pi', 'ña'], '1f34d', <String>['comida', 'fruta', 'amarillo', 'colombia']),
    VocabItem('mango', 'mango', 'm', <String>['man', 'go'], '1f96d', <String>['comida', 'fruta', 'amarillo', 'colombia', 'arbol']),
    VocabItem('pera', 'pera', 'f', <String>['pe', 'ra'], '1f350', <String>['comida', 'fruta', 'verde', 'arbol']),
    VocabItem('limon', 'limón', 'm', <String>['li', 'món'], '1f34b', <String>['comida', 'fruta', 'amarillo', 'arbol', 'acido']),
    VocabItem('cereza', 'cereza', 'f', <String>['ce', 're', 'za'], '1f352', <String>['comida', 'fruta', 'rojo', 'arbol']),
    VocabItem('coco', 'coco', 'm', <String>['co', 'co'], '1f965', <String>['comida', 'fruta', 'cafe', 'colombia', 'arbol']),
    VocabItem('kiwi', 'kiwi', 'm', <String>['ki', 'wi'], '1f95d', <String>['comida', 'fruta', 'verde']),
    VocabItem('durazno', 'durazno', 'm', <String>['du', 'raz', 'no'], '1f351', <String>['comida', 'fruta', 'naranja', 'arbol']),
    VocabItem('melon', 'melón', 'm', <String>['me', 'lón'], '1f348', <String>['comida', 'fruta', 'verde', 'grande']),

    // Verduras
    VocabItem('zanahoria', 'zanahoria', 'f', <String>['za', 'na', 'ho', 'ria'], '1f955', <String>['comida', 'verdura', 'naranja', 'tierra']),
    VocabItem('maiz', 'maíz', 'm', <String>['ma', 'íz'], '1f33d', <String>['comida', 'verdura', 'amarillo', 'colombia']),
    VocabItem('tomate', 'tomate', 'm', <String>['to', 'ma', 'te'], '1f345', <String>['comida', 'verdura', 'rojo']),
    VocabItem('papa', 'papa', 'f', <String>['pa', 'pa'], '1f954', <String>['comida', 'verdura', 'cafe', 'tierra', 'colombia', 'andes']),
    VocabItem('cebolla', 'cebolla', 'f', <String>['ce', 'bo', 'lla'], '1f9c5', <String>['comida', 'verdura', 'tierra']),
    VocabItem('brocoli', 'brócoli', 'm', <String>['bró', 'co', 'li'], '1f966', <String>['comida', 'verdura', 'verde']),
    VocabItem('lechuga', 'lechuga', 'f', <String>['le', 'chu', 'ga'], '1f96c', <String>['comida', 'verdura', 'verde']),
    VocabItem('aji', 'ají', 'm', <String>['a', 'jí'], '1f336', <String>['comida', 'verdura', 'rojo', 'picante']),
    VocabItem('aguacate', 'aguacate', 'm', <String>['a', 'gua', 'ca', 'te'], '1f951', <String>['comida', 'verdura', 'verde', 'colombia', 'arbol']),
    VocabItem('berenjena', 'berenjena', 'f', <String>['be', 'ren', 'je', 'na'], '1f346', <String>['comida', 'verdura', 'morado']),
    VocabItem('pepino', 'pepino', 'm', <String>['pe', 'pi', 'no'], '1f952', <String>['comida', 'verdura', 'verde']),

    // Otras comidas
    VocabItem('pan', 'pan', 'm', <String>['pan'], '1f35e', <String>['comida', 'cocina', 'desayuno']),
    VocabItem('queso', 'queso', 'm', <String>['que', 'so'], '1f9c0', <String>['comida', 'cocina', 'leche', 'desayuno']),
    VocabItem('huevo', 'huevo', 'm', <String>['hue', 'vo'], '1f95a', <String>['comida', 'cocina', 'desayuno', 'granja']),
    VocabItem('arroz', 'arroz', 'm', <String>['a', 'rroz'], '1f35a', <String>['comida', 'cocina', 'almuerzo']),
    VocabItem('pollo', 'pollo', 'm', <String>['po', 'llo'], '1f357', <String>['comida', 'cocina', 'almuerzo']),
    VocabItem('leche', 'leche', 'f', <String>['le', 'che'], '1f95b', <String>['comida', 'bebida', 'desayuno', 'leche']),
    VocabItem('helado', 'helado', 'm', <String>['he', 'la', 'do'], '1f366', <String>['comida', 'dulce', 'frio']),
    VocabItem('galleta', 'galleta', 'f', <String>['ga', 'lle', 'ta'], '1f36a', <String>['comida', 'dulce']),
    VocabItem('torta', 'torta', 'f', <String>['tor', 'ta'], '1f382', <String>['comida', 'dulce', 'fiesta']),
    VocabItem('pizza', 'pizza', 'f', <String>['pi', 'zza'], '1f355', <String>['comida', 'almuerzo']),
    VocabItem('chocolate', 'chocolate', 'm', <String>['cho', 'co', 'la', 'te'], '1f36b', <String>['comida', 'dulce']),
    VocabItem('miel', 'miel', 'f', <String>['miel'], '1f36f', <String>['comida', 'dulce', 'miel']),
    VocabItem('jugo', 'jugo', 'm', <String>['ju', 'go'], '1f9c3', <String>['comida', 'bebida']),
    VocabItem('sopa', 'sopa', 'f', <String>['so', 'pa'], '1f963', <String>['comida', 'almuerzo', 'caliente']),
    VocabItem('arepa', 'arepa', 'f', <String>['a', 're', 'pa'], '1fad3', <String>['comida', 'desayuno', 'colombia', 'maiz']),

    // Vehículos
    VocabItem('carro', 'carro', 'm', <String>['ca', 'rro'], '1f697', <String>['vehiculo', 'tierra', 'ruedas', 'ciudad']),
    VocabItem('bus', 'bus', 'm', <String>['bus'], '1f68c', <String>['vehiculo', 'tierra', 'ruedas', 'ciudad', 'grande']),
    VocabItem('bicicleta', 'bicicleta', 'f', <String>['bi', 'ci', 'cle', 'ta'], '1f6b2', <String>['vehiculo', 'tierra', 'ruedas', 'ciudad']),
    VocabItem('moto', 'moto', 'f', <String>['mo', 'to'], '1f3cd', <String>['vehiculo', 'tierra', 'ruedas', 'ciudad']),
    VocabItem('tren', 'tren', 'm', <String>['tren'], '1f682', <String>['vehiculo', 'tierra', 'ruedas', 'grande']),
    VocabItem('helicoptero', 'helicóptero', 'm', <String>['he', 'li', 'cóp', 'te', 'ro'], '1f681', <String>['vehiculo', 'aire', 'vuela']),
    VocabItem('avion', 'avión', 'm', <String>['a', 'vión'], '2708', <String>['vehiculo', 'aire', 'vuela', 'grande']),
    VocabItem('cohete', 'cohete', 'm', <String>['co', 'he', 'te'], '1f680', <String>['vehiculo', 'aire', 'vuela', 'espacio']),
    VocabItem('velero', 'velero', 'm', <String>['ve', 'le', 'ro'], '26f5', <String>['vehiculo', 'agua', 'nada', 'mar']),
    VocabItem('barco', 'barco', 'm', <String>['bar', 'co'], '1f6a2', <String>['vehiculo', 'agua', 'nada', 'mar', 'grande']),
    VocabItem('bomberos', 'carro de bomberos', 'm', <String>['bom', 'be', 'ros'], '1f692', <String>['vehiculo', 'tierra', 'ruedas', 'ciudad', 'ayuda']),
    VocabItem('ambulancia', 'ambulancia', 'f', <String>['am', 'bu', 'lan', 'cia'], '1f691', <String>['vehiculo', 'tierra', 'ruedas', 'ciudad', 'ayuda']),
    VocabItem('tractor', 'tractor', 'm', <String>['trac', 'tor'], '1f69c', <String>['vehiculo', 'tierra', 'ruedas', 'granja']),
    VocabItem('patineta', 'patineta', 'f', <String>['pa', 'ti', 'ne', 'ta'], '1f6f4', <String>['vehiculo', 'tierra', 'ruedas', 'juguete']),
    VocabItem('camion', 'camión', 'm', <String>['ca', 'mión'], '1f69a', <String>['vehiculo', 'tierra', 'ruedas', 'grande']),

    // Ropa
    VocabItem('camiseta', 'camiseta', 'f', <String>['ca', 'mi', 'se', 'ta'], '1f455', <String>['ropa', 'calor']),
    VocabItem('pantalon', 'pantalón', 'm', <String>['pan', 'ta', 'lón'], '1f456', <String>['ropa']),
    VocabItem('vestido', 'vestido', 'm', <String>['ves', 'ti', 'do'], '1f457', <String>['ropa']),
    VocabItem('zapato', 'zapato', 'm', <String>['za', 'pa', 'to'], '1f45f', <String>['ropa', 'pies']),
    VocabItem('gorra', 'gorra', 'f', <String>['go', 'rra'], '1f9e2', <String>['ropa', 'cabeza', 'calor', 'sol']),
    VocabItem('medias', 'medias', 'f', <String>['me', 'dias'], '1f9e6', <String>['ropa', 'pies', 'plural']),
    VocabItem('guantes', 'guantes', 'm', <String>['guan', 'tes'], '1f9e4', <String>['ropa', 'frio', 'manos', 'plural']),
    VocabItem('bufanda', 'bufanda', 'f', <String>['bu', 'fan', 'da'], '1f9e3', <String>['ropa', 'frio']),
    VocabItem('sombrero', 'sombrero', 'm', <String>['som', 'bre', 'ro'], '1f452', <String>['ropa', 'cabeza', 'sol']),
    VocabItem('botas', 'botas', 'f', <String>['bo', 'tas'], '1f97e', <String>['ropa', 'pies', 'lluvia', 'plural']),
    VocabItem('gafas', 'gafas de sol', 'f', <String>['ga', 'fas'], '1f576', <String>['ropa', 'sol', 'calor', 'plural']),
    VocabItem('maleta', 'maleta', 'f', <String>['ma', 'le', 'ta'], '1f392', <String>['objeto', 'escuela']),
    VocabItem('chaqueta', 'chaqueta', 'f', <String>['cha', 'que', 'ta'], '1f9e5', <String>['ropa', 'frio']),

    // Cuerpo
    VocabItem('oreja', 'oreja', 'f', <String>['o', 're', 'ja'], '1f442', <String>['cuerpo', 'cabeza', 'oido']),
    VocabItem('nariz', 'nariz', 'f', <String>['na', 'riz'], '1f443', <String>['cuerpo', 'cabeza', 'olfato']),
    VocabItem('ojo', 'ojo', 'm', <String>['o', 'jo'], '1f441', <String>['cuerpo', 'cabeza', 'vista']),
    VocabItem('boca', 'boca', 'f', <String>['bo', 'ca'], '1f444', <String>['cuerpo', 'cabeza', 'gusto']),
    VocabItem('lengua', 'lengua', 'f', <String>['len', 'gua'], '1f445', <String>['cuerpo', 'cabeza', 'gusto']),
    VocabItem('diente', 'diente', 'm', <String>['dien', 'te'], '1f9b7', <String>['cuerpo', 'cabeza']),
    VocabItem('mano', 'mano', 'f', <String>['ma', 'no'], '1f590', <String>['cuerpo', 'tacto']),
    VocabItem('pie', 'pie', 'm', <String>['pie'], '1f9b6', <String>['cuerpo']),
    VocabItem('pierna', 'pierna', 'f', <String>['pier', 'na'], '1f9b5', <String>['cuerpo']),
    VocabItem('brazo', 'brazo', 'm', <String>['bra', 'zo'], '1f4aa', <String>['cuerpo']),
    VocabItem('cerebro', 'cerebro', 'm', <String>['ce', 're', 'bro'], '1f9e0', <String>['cuerpo', 'organo']),
    VocabItem('corazon', 'corazón', 'm', <String>['co', 'ra', 'zón'], '1fac0', <String>['cuerpo', 'organo']),
    VocabItem('pulmones', 'pulmones', 'm', <String>['pul', 'mo', 'nes'], '1fac1', <String>['cuerpo', 'organo', 'plural']),
    VocabItem('hueso', 'hueso', 'm', <String>['hue', 'so'], '1f9b4', <String>['cuerpo']),

    // Casa, escuela y objetos
    VocabItem('casa', 'casa', 'f', <String>['ca', 'sa'], '1f3e0', <String>['objeto', 'lugar']),
    VocabItem('puerta', 'puerta', 'f', <String>['puer', 'ta'], '1f6aa', <String>['objeto', 'casa']),
    VocabItem('silla', 'silla', 'f', <String>['si', 'lla'], '1fa91', <String>['objeto', 'casa', 'mueble']),
    VocabItem('cama', 'cama', 'f', <String>['ca', 'ma'], '1f6cf', <String>['objeto', 'casa', 'mueble', 'dormir']),
    VocabItem('sofa', 'sofá', 'm', <String>['so', 'fá'], '1f6cb', <String>['objeto', 'casa', 'mueble']),
    VocabItem('ventana', 'ventana', 'f', <String>['ven', 'ta', 'na'], '1fa9f', <String>['objeto', 'casa']),
    VocabItem('llave', 'llave', 'f', <String>['lla', 've'], '1f511', <String>['objeto', 'casa']),
    VocabItem('reloj', 'reloj', 'm', <String>['re', 'loj'], '23f0', <String>['objeto', 'casa', 'tiempo']),
    VocabItem('bombillo', 'bombillo', 'm', <String>['bom', 'bi', 'llo'], '1f4a1', <String>['objeto', 'casa', 'luz']),
    VocabItem('libros', 'libros', 'm', <String>['li', 'bros'], '1f4da', <String>['objeto', 'escuela', 'plural']),
    VocabItem('lapiz', 'lápiz', 'm', <String>['lá', 'piz'], '270f', <String>['objeto', 'escuela', 'escribir']),
    VocabItem('regla', 'regla', 'f', <String>['re', 'gla'], '1f4cf', <String>['objeto', 'escuela', 'medir']),
    VocabItem('tijeras', 'tijeras', 'f', <String>['ti', 'je', 'ras'], '2702', <String>['objeto', 'escuela', 'plural', 'cuidado']),
    VocabItem('crayon', 'crayón', 'm', <String>['cra', 'yón'], '1f58d', <String>['objeto', 'escuela', 'pintar']),
    VocabItem('libro', 'libro', 'm', <String>['li', 'bro'], '1f4d6', <String>['objeto', 'escuela', 'leer']),
    VocabItem('pincel', 'pincel', 'm', <String>['pin', 'cel'], '1f58c', <String>['objeto', 'escuela', 'pintar']),
    VocabItem('balon', 'balón', 'm', <String>['ba', 'lón'], '26bd', <String>['objeto', 'juguete', 'deporte']),
    VocabItem('oso_peluche', 'oso de peluche', 'm', <String>['pe', 'lu', 'che'], '1f9f8', <String>['objeto', 'juguete']),
    VocabItem('cometa', 'cometa', 'f', <String>['co', 'me', 'ta'], '1fa81', <String>['objeto', 'juguete', 'aire', 'viento']),
    VocabItem('globo', 'globo', 'm', <String>['glo', 'bo'], '1f388', <String>['objeto', 'juguete', 'fiesta']),
    VocabItem('rompecabezas', 'rompecabezas', 'm', <String>['rom', 'pe', 'ca', 'be', 'zas'], '1f9e9', <String>['objeto', 'juguete']),
    VocabItem('dado', 'dado', 'm', <String>['da', 'do'], '1f3b2', <String>['objeto', 'juguete']),
    VocabItem('cepillo', 'cepillo de dientes', 'm', <String>['ce', 'pi', 'llo'], '1faa5', <String>['objeto', 'bano', 'aseo']),
    VocabItem('jabon', 'jabón', 'm', <String>['ja', 'bón'], '1f9fc', <String>['objeto', 'bano', 'aseo']),
    VocabItem('banera', 'bañera', 'f', <String>['ba', 'ñe', 'ra'], '1f6c1', <String>['objeto', 'bano', 'aseo', 'agua']),
    VocabItem('balde', 'balde', 'm', <String>['bal', 'de'], '1faa3', <String>['objeto', 'casa', 'agua']),
    VocabItem('escoba', 'escoba', 'f', <String>['es', 'co', 'ba'], '1f9f9', <String>['objeto', 'casa', 'limpiar']),
    VocabItem('plato', 'plato', 'm', <String>['pla', 'to'], '1f37d', <String>['objeto', 'cocina']),
    VocabItem('cuchara', 'cuchara', 'f', <String>['cu', 'cha', 'ra'], '1f944', <String>['objeto', 'cocina']),
    VocabItem('tenedor', 'tenedor', 'm', <String>['te', 'ne', 'dor'], '1f374', <String>['objeto', 'cocina']),
    VocabItem('olla', 'olla', 'f', <String>['o', 'lla'], '1f372', <String>['objeto', 'cocina', 'caliente']),
    VocabItem('tetera', 'tetera', 'f', <String>['te', 'te', 'ra'], '1fad6', <String>['objeto', 'cocina', 'caliente']),
    VocabItem('telefono', 'teléfono', 'm', <String>['te', 'lé', 'fo', 'no'], '1f4f1', <String>['objeto', 'casa', 'pantalla']),
    VocabItem('computador', 'computador', 'm', <String>['com', 'pu', 'ta', 'dor'], '1f4bb', <String>['objeto', 'casa', 'pantalla']),
    VocabItem('television', 'televisor', 'm', <String>['te', 'le', 'vi', 'sor'], '1f4fa', <String>['objeto', 'casa', 'pantalla']),
    VocabItem('camara', 'cámara', 'f', <String>['cá', 'ma', 'ra'], '1f4f7', <String>['objeto', 'casa']),

    // Instrumentos
    VocabItem('guitarra', 'guitarra', 'f', <String>['gui', 'ta', 'rra'], '1f3b8', <String>['objeto', 'instrumento', 'cuerdas']),
    VocabItem('tambor', 'tambor', 'm', <String>['tam', 'bor'], '1fa98', <String>['objeto', 'instrumento', 'percusion', 'colombia']),
    VocabItem('trompeta', 'trompeta', 'f', <String>['trom', 'pe', 'ta'], '1f3ba', <String>['objeto', 'instrumento', 'viento']),
    VocabItem('violin', 'violín', 'm', <String>['vio', 'lín'], '1f3bb', <String>['objeto', 'instrumento', 'cuerdas']),
    VocabItem('piano', 'piano', 'm', <String>['pia', 'no'], '1f3b9', <String>['objeto', 'instrumento', 'teclas']),
    VocabItem('acordeon', 'acordeón', 'm', <String>['a', 'cor', 'de', 'ón'], '1fa97', <String>['objeto', 'instrumento', 'viento', 'colombia']),
    VocabItem('maracas', 'maracas', 'f', <String>['ma', 'ra', 'cas'], '1fa87', <String>['objeto', 'instrumento', 'percusion', 'colombia', 'plural']),
    VocabItem('flauta', 'flauta', 'f', <String>['flau', 'ta'], '1fa88', <String>['objeto', 'instrumento', 'viento']),

    // Naturaleza y clima
    VocabItem('sol', 'sol', 'm', <String>['sol'], '2600', <String>['naturaleza', 'clima', 'cielo', 'dia', 'calor', 'luz']),
    VocabItem('luna', 'luna', 'f', <String>['lu', 'na'], '1f319', <String>['naturaleza', 'cielo', 'noche', 'espacio']),
    VocabItem('estrella', 'estrella', 'f', <String>['es', 'tre', 'lla'], '2b50', <String>['naturaleza', 'cielo', 'noche', 'espacio']),
    VocabItem('nube', 'nube', 'f', <String>['nu', 'be'], '2601', <String>['naturaleza', 'clima', 'cielo', 'dia']),
    VocabItem('lluvia', 'lluvia', 'f', <String>['llu', 'via'], '1f327', <String>['naturaleza', 'clima', 'agua', 'frio']),
    VocabItem('tormenta', 'tormenta', 'f', <String>['tor', 'men', 'ta'], '26c8', <String>['naturaleza', 'clima', 'peligro']),
    VocabItem('arcoiris', 'arcoíris', 'm', <String>['ar', 'co', 'í', 'ris'], '1f308', <String>['naturaleza', 'clima', 'cielo', 'colores']),
    VocabItem('nieve', 'nieve', 'f', <String>['nie', 've'], '2744', <String>['naturaleza', 'clima', 'frio', 'agua']),
    VocabItem('ola', 'ola', 'f', <String>['o', 'la'], '1f30a', <String>['naturaleza', 'mar', 'agua']),
    VocabItem('fuego', 'fuego', 'm', <String>['fue', 'go'], '1f525', <String>['naturaleza', 'calor', 'peligro']),
    VocabItem('arbol', 'árbol', 'm', <String>['ár', 'bol'], '1f333', <String>['naturaleza', 'planta', 'bosque', 'verde']),
    VocabItem('pino', 'pino', 'm', <String>['pi', 'no'], '1f332', <String>['naturaleza', 'planta', 'bosque', 'frio']),
    VocabItem('palmera', 'palmera', 'f', <String>['pal', 'me', 'ra'], '1f334', <String>['naturaleza', 'planta', 'playa', 'calor', 'colombia']),
    VocabItem('cactus', 'cactus', 'm', <String>['cac', 'tus'], '1f335', <String>['naturaleza', 'planta', 'desierto', 'calor']),
    VocabItem('flor', 'flor', 'f', <String>['flor'], '1f338', <String>['naturaleza', 'planta', 'jardin', 'rosado']),
    VocabItem('girasol', 'girasol', 'm', <String>['gi', 'ra', 'sol'], '1f33b', <String>['naturaleza', 'planta', 'jardin', 'amarillo', 'sol']),
    VocabItem('rosa', 'rosa', 'f', <String>['ro', 'sa'], '1f339', <String>['naturaleza', 'planta', 'jardin', 'rojo', 'colombia']),
    VocabItem('tulipan', 'tulipán', 'm', <String>['tu', 'li', 'pán'], '1f337', <String>['naturaleza', 'planta', 'jardin']),
    VocabItem('hongo', 'hongo', 'm', <String>['hon', 'go'], '1f344', <String>['naturaleza', 'bosque']),
    VocabItem('trebol', 'trébol', 'm', <String>['tré', 'bol'], '1f340', <String>['naturaleza', 'planta', 'verde']),
    VocabItem('hoja', 'hoja', 'f', <String>['ho', 'ja'], '1f343', <String>['naturaleza', 'planta', 'verde', 'viento']),
    VocabItem('piedra', 'piedra', 'f', <String>['pie', 'dra'], '1faa8', <String>['naturaleza', 'tierra', 'dura']),
    VocabItem('montana', 'montaña', 'f', <String>['mon', 'ta', 'ña'], '26f0', <String>['naturaleza', 'lugar', 'andes', 'frio']),
    VocabItem('volcan', 'volcán', 'm', <String>['vol', 'cán'], '1f30b', <String>['naturaleza', 'lugar', 'calor', 'colombia']),
    VocabItem('isla', 'isla', 'f', <String>['is', 'la'], '1f3dd', <String>['naturaleza', 'lugar', 'mar', 'playa']),
    VocabItem('tierra', 'planeta Tierra', 'm', <String>['tie', 'rra'], '1f30d', <String>['naturaleza', 'espacio']),
    VocabItem('semilla', 'semilla', 'f', <String>['se', 'mi', 'lla'], '1f331', <String>['naturaleza', 'planta', 'crece']),
  ];

  static VocabItem? byId(String id) {
    for (final VocabItem v in all) {
      if (v.id == id) {
        return v;
      }
    }
    return null;
  }

  static List<VocabItem> withTag(String tag) => all.where((VocabItem v) => v.has(tag)).toList();

  static List<VocabItem> withAllTags(List<String> tags) =>
      all.where((VocabItem v) => tags.every((String t) => v.has(t))).toList();

  static List<VocabItem> withoutTag(String tag) => all.where((VocabItem v) => !v.has(tag)).toList();

  /// Palabras de un número de sílabas (para armar palabras).
  static List<VocabItem> withSyllables(int n) => all.where((VocabItem v) => v.silabas.length == n && !v.nombre.contains(' ')).toList();

  /// Palabras que empiezan por una letra (para sonidos iniciales).
  static List<VocabItem> startingWith(String letter) {
    final String l = _plain(letter);
    return all.where((VocabItem v) => _plain(v.nombre.substring(0, 1)) == l && !v.nombre.contains(' ')).toList();
  }

  static String _plain(String s) {
    const Map<String, String> m = <String, String>{'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u', 'ü': 'u'};
    final String low = s.toLowerCase();
    return m[low] ?? low;
  }
}
