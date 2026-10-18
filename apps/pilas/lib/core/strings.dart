import 'es.dart';

/// Textos de la interfaz. Pilas es solo en español (de Colombia).
class S {
  S._();

  static const String appName = 'Pilas';
  static const String lema = 'Juega, piensa, aprende';

  // Perfiles
  static const String quienJuega = '¿Quién va a jugar?';
  static const String nuevoPerfil = 'Nuevo perfil';
  static const String soyAdulto = 'Soy adulto';
  static const String nombre = 'Nombre o apodo';
  static const String edad = 'Edad';
  static const String anios = 'años';
  static const String elegirAvatar = 'Elige un animal';
  static const String guardar = 'Guardar';
  static const String cancelar = 'Cancelar';
  static const String listo = 'Listo';
  static const String borrar = 'Borrar';
  static const String editar = 'Editar';
  static const String mesNacimiento = 'Mes de nacimiento';
  static const String anioNacimiento = 'Año de nacimiento';
  static const String tramoAuto = 'Según la edad';
  static const String zurdo = 'Modo zurdo';
  static const String zurdoDetalle = 'Pone los botones y las herramientas de los juegos al lado izquierdo, y en los trazos de pre-escritura las líneas acostadas empiezan por la derecha.';
  static const String cambiarConDescanso = 'Otro jugador está en su descanso. Un adulto confirma el cambio de jugador.';

  // Inicio de los niños
  static String hola(String nombre) => '¡Hola, $nombre!';

  /// Saludo que dice la voz: sin el nombre del niño, para que ningún dato del
  /// perfil llegue al motor de voz del sistema.
  static const String holaVoz = '¡Hola!';
  static const String queQuieresJugar = '¿Qué quieres jugar hoy?';
  static const String misPegatinas = 'Mis pegatinas';
  static const String misDibujos = 'Mis dibujos';
  static const String cambiarJugador = 'Cambiar de jugador';
  static const String nivel = 'Nivel';
  static const String jugar = 'Jugar';
  static const String repetir = 'Repetir';
  static const String pista = 'Pista';
  static const String siguiente = 'Siguiente';
  static const String otraVez = 'Otra vez';
  static const String salir = 'Salir';
  static const String seguirJugando = 'Seguir jugando';
  static const String muyBien = '¡Muy bien!';
  static const String excelente = '¡Excelente!';
  static const String casi = 'Casi. Mira la pista.';
  static const String asiEs = 'Así es';
  static const String nuevoNivel = '¡Subiste de nivel!';
  static const String nuevaPegatina = '¡Nueva pegatina!';
  static const String ganastePegatina = '¡Ganaste una pegatina nueva!';
  static const String loLograste = '¡Lo lograste!';
  static const String listoExclamacion = '¡Listo!';

  // Carrera de cálculo
  static const String terminasteCarrera = '¡Terminaste la carrera!';
  static String acertasteDe(int n, int total) {
    if (n == total) {
      return '¡Acertaste todas al primer intento!';
    }
    if (n == 0) {
      return 'Esta vez ninguna salió al primer intento. ¡Vamos por otra!';
    }
    return 'Acertaste ${Es.numero(n, femenino: true)} de ${Es.numero(total, femenino: true)} al primer intento.';
  }

  static const String nuevaMarca = '¡Nueva marca!';
  static const String otraCarrera = 'Otra carrera';
  static String preguntaDe(int n, int total) => 'Operación $n de $total';
  static const String aciertos = 'Aciertos';
  static const String tuMarca = 'Tu marca';
  static const String sinVozTitulo = 'Este dispositivo no tiene voz en español';
  static const String sinVozTexto = 'Los juegos de 3 a 6 años se guían por la voz. Un adulto puede instalar una voz en español en los ajustes de texto a voz del teléfono o la tableta.';

  // Descanso
  static const String horaDeDescansar = '¡Hora de descansar!';
  static const String descansoTexto = 'Ya jugaste un buen rato. Estira el cuerpo, toma agua y vuelve cuando termine el descanso.';
  static const String descansoTerminado = '¡Listo! Ya puedes volver a jugar.';
  static const String volverAJugar = 'Volver a jugar';
  static const String masTiempo = 'Más tiempo (adulto)';
  static const String masTiempoRazon = 'Dar 10 minutos más de juego';
  static String quedan(int min, int seg) => 'Faltan ${min.toString()}:${seg.toString().padLeft(2, '0')}';

  // Puerta parental
  static const String paraAdultos = 'Para adultos';
  static const String esParaUnAdulto = 'Esto es para un adulto.';
  static const String resuelveParaEntrar = 'Escribe en cifras el resultado de la operación.';
  static const String respuesta = 'Respuesta';
  static const String respuestaEnCifras = 'Resultado en cifras';
  static const String entrar = 'Entrar';
  static const String respuestaIncorrecta = 'Esa no es. Inténtalo con la nueva operación.';
  static String esperaPuerta(int s) => 'Demasiados intentos. Espera $s segundos.';

  // Panel de padres
  static const String panelAdultos = 'Panel de adultos';
  static const String ninos = 'Niños';
  static const String ajustes = 'Ajustes';
  static const String informe = 'Informe';
  static const String informePdf = 'Informe en PDF';
  static const String modoDocente = 'Modo docente';
  static const String guiaFamilias = 'Guía para familias';
  static const String creditos = 'Créditos y licencias';
  static const String politicaPrivacidad = 'Política de privacidad';
  static const String licenciasSoftware = 'Licencias de software';
  static const String acercaDe = 'Acerca de Pilas';
  static const String voz = 'Voz que lee las instrucciones';
  static const String velocidadVoz = 'Velocidad de la voz';
  static const String sonidos = 'Sonidos';
  static const String limiteSesion = 'Tiempo por sesión de cada niño';
  static const String limiteDetalle =
      'Cada niño tiene su propio tiempo. Solo cuenta el tiempo con Pilas abierta en pantalla; la sesión termina tras 10 minutos sin jugar. Al cumplirse el tiempo aparece un descanso de 10 minutos que no se salta cerrando la app ni cambiando de jugador sin un adulto. Un adulto puede dar 10 minutos más. La OMS recomienda no más de una hora de pantalla al día entre los 2 y los 4 años.';
  static const String sinLimite = 'Sin límite';
  static String minutos(int n) => n == 1 ? '1 minuto' : '$n minutos';
  static const String textoGrande = 'Texto grande';
  static const String textoGrandeDetalle = 'Agranda la letra un 25\u00A0% sobre el tamaño elegido en el teléfono, con un tope de 1,5 veces.';
  static const String fuenteDislexia = 'Fuente para dislexia';
  static const String altoContraste = 'Alto contraste';
  static const String altoContrasteDetalle = 'Fondo blanco, texto negro y bordes marcados en toda la app y en los juegos; las figuras de colores llevan además una marca propia de cada color.';
  static const String hoy = 'Hoy';
  static const String ultimos7 = 'Últimos 7 días';
  static const String habilidadesLogradas = 'Habilidades logradas';
  static String habilidadesDelTramo(String tramo) => 'Habilidades de $tramo';
  static const String aciertosPrimerIntento = 'Aciertos al primer intento';
  static const String comoSeLogra = 'Una habilidad se logra al dominar el último nivel del juego que la evalúa, contando solo las respuestas acertadas al primer intento.';
  static const String soloJuegoLibre = 'En este tramo el área solo tiene juego libre (colorear y dibujar): no tiene habilidades evaluadas.';
  static const String pegatinas = 'Pegatinas';
  static const String ultimasSesiones = 'Últimas sesiones';
  static const String sinSesiones = 'Todavía no ha jugado.';
  static const String exportarDatos = 'Exportar datos';
  static const String importarDatos = 'Importar datos';
  static const String borrarPerfil = 'Borrar perfil';
  static String confirmarBorrar(String nombre) => '¿Borrar el perfil de $nombre, todo su avance y sus dibujos? No se puede deshacer.';
  static const String grupos = 'Grupos';
  static const String nuevoGrupo = 'Nuevo grupo';
  static const String nombreGrupo = 'Nombre del grupo';
  static const String agregarNinos = 'Agregar niños';
  static const String exportarCsv = 'Exportar CSV';
  static const String informeGrupo = 'Informe del grupo';
  static const String compartir = 'Compartir';
  static const String avisos = 'Avisos';
  static const String entendido = 'Entendido';

  // Áreas y varios
  static const String sinConexion = 'Funciona sin internet, sin anuncios y sin cuenta.';
  static const String privacidad = 'Los datos de los niños se guardan en este dispositivo y no se envían a ningún servidor.';
  static const String soporteUrl = 'https://github.com/jairoruidiazi-creator/jairoruidiazi-creator-apps-gratis/blob/main/docs/SOPORTE.md';
  static const String soporteTexto =
      'Para preguntas, sugerencias o para reportar un problema, abre un reporte desde la página de ayuda de Pilas: sirve desde Android, iPhone o un computador. Para un asunto privado, abre un reporte con el título «Contacto privado», sin datos personales, y te responderemos por un canal privado.';
}
