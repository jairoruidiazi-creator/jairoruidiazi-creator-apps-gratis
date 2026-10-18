import 'package:pilas/engine/game_def.dart';
import 'package:pilas/engine/game_registry.dart';
import 'package:pilas/games/banco/bank_generator.dart';
import 'package:pilas/games/banco/cuerpo_bank.dart';
import 'package:pilas/games/banco/decisiones_bank.dart';
import 'package:pilas/games/banco/laboratorio_bank.dart';
import 'package:pilas/games/carrera/carrera_generator.dart';
import 'package:pilas/games/choice/choice_round.dart';
import 'package:pilas/games/clasifica/clasifica_generator.dart';
import 'package:pilas/games/cocina/cocina_generator.dart';
import 'package:pilas/games/emociones/emociones_generator.dart';
import 'package:pilas/games/figuras/figuras_generator.dart';
import 'package:pilas/games/intruso/intruso_generator.dart';
import 'package:pilas/games/patrones/patrones_generator.dart';
import 'package:pilas/games/reloj/reloj_generator.dart';
import 'package:pilas/games/sonidos/sonidos_generator.dart';

/// Un juego de elegir y cómo crear su generador (el mismo que usa el registro).
class GeneratorCase {
  GeneratorCase(this.gameId, this.generator);

  final String gameId;
  final ChoiceGenerator Function() generator;

  GameDef get game => GameRegistry.byId(gameId)!;
}

/// Todos los juegos de elegir de la app (la tienda va aparte porque también
/// tiene rondas de pagar).
List<GeneratorCase> choiceGeneratorCases() => <GeneratorCase>[
      GeneratorCase('patrones', () => PatronesGenerator()),
      GeneratorCase('intruso', () => IntrusoGenerator()),
      GeneratorCase('carrera', () => CarreraGenerator()),
      GeneratorCase('reloj', () => RelojGenerator()),
      GeneratorCase('sonidos', () => SonidosGenerator()),
      GeneratorCase('cocina', () => CocinaGenerator()),
      GeneratorCase('figuras', () => FigurasGenerator()),
      GeneratorCase('clasifica', () => ClasificaGenerator()),
      GeneratorCase('cuerpo', () => BankGenerator(CuerpoBank.all, pistaGeneral: CuerpoBank.pistaGeneral)),
      GeneratorCase('laboratorio', () => BankGenerator(LaboratorioBank.all, pistaGeneral: LaboratorioBank.pistaGeneral)),
      GeneratorCase('emociones', () => EmocionesGenerator()),
      GeneratorCase('decisiones', () => BankGenerator(DecisionesBank.all, pistaGeneral: DecisionesBank.pistaGeneral)),
    ];
