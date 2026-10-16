/// Textos de la interfaz en español. Cuando entre el inglés (v2) esta clase
/// pasa a ser una interfaz con dos implementaciones.
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
  static const String elegirAvatar = 'Elige tu animal';
  static const String guardar = 'Guardar';
  static const String cancelar = 'Cancelar';
  static const String listo = 'Listo';
  static const String borrar = 'Borrar';
  static const String editar = 'Editar';
  static const String mesNacimiento = 'Mes de nacimiento';
  static const String anioNacimiento = 'Año de nacimiento';
  static const String tramoAuto = 'Según la edad';
  static const String tramoManual = 'Nivel fijado por el adulto';
  static const String zurdo = 'Botones a la izquierda (zurdo)';

  // Inicio de los niños
  static String hola(String nombre) => '¡Hola, $nombre!';
  static const String queQuieresJugar = '¿Qué quieres jugar hoy?';
  static const String misPegatinas = 'Mis pegatinas';
  static const String misDibujos = 'Mis dibujos';
  static const String cambiarJugador = 'Cambiar';
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
  static const String asiEs = 'Así es:';
  static const String nuevoNivel = '¡Subiste de nivel!';
  static const String nuevaPegatina = '¡Nueva pegatina!';
  static const String horaDeDescansar = '¡Hora de descansar!';
  static const String descansoTexto = 'Ya jugaste un buen rato. Estira el cuerpo, toma agua y vuelve luego.';
  static const String masTiempo = 'Más tiempo (adulto)';

  // Puerta parental
  static const String paraAdultos = 'Para adultos';
  static const String resuelveParaEntrar = 'Resuelve la operación para entrar.';
  static const String respuesta = 'Respuesta';
  static const String entrar = 'Entrar';
  static const String respuestaIncorrecta = 'Esa no es. Inténtalo de nuevo.';

  // Panel de padres
  static const String panelAdultos = 'Panel de adultos';
  static const String ninos = 'Niños';
  static const String ajustes = 'Ajustes';
  static const String informe = 'Informe';
  static const String informePdf = 'Informe en PDF';
  static const String modoDocente = 'Modo docente';
  static const String creditos = 'Créditos y licencias';
  static const String acercaDe = 'Acerca de Pilas';
  static const String voz = 'Voz que lee las instrucciones';
  static const String velocidadVoz = 'Velocidad de la voz';
  static const String sonidos = 'Sonidos';
  static const String limiteSesion = 'Tiempo por sesión';
  static const String sinLimite = 'Sin límite';
  static String minutos(int n) => n == 1 ? '1 minuto' : '$n minutos';
  static const String textoGrande = 'Texto grande';
  static const String fuenteDislexia = 'Fuente para dislexia';
  static const String altoContraste = 'Alto contraste';
  static const String hoy = 'Hoy';
  static const String estaSemana = 'Esta semana';
  static const String habilidadesLogradas = 'Habilidades logradas';
  static const String pegatinas = 'Pegatinas';
  static const String ultimasSesiones = 'Últimas sesiones';
  static const String sinSesiones = 'Todavía no ha jugado.';
  static const String exportarDatos = 'Exportar datos';
  static const String importarDatos = 'Importar datos';
  static const String borrarPerfil = 'Borrar perfil';
  static String confirmarBorrar(String nombre) => '¿Borrar el perfil de $nombre y todo su progreso? No se puede deshacer.';
  static const String grupos = 'Grupos';
  static const String nuevoGrupo = 'Nuevo grupo';
  static const String nombreGrupo = 'Nombre del grupo';
  static const String agregarNinos = 'Agregar niños';
  static const String exportarCsv = 'Exportar CSV';
  static const String informeGrupo = 'Informe del grupo';

  // Áreas y varios
  static const String sinConexion = 'Funciona sin internet, sin anuncios y sin cuenta.';
  static const String privacidad = 'Los datos de los niños quedan solo en este dispositivo.';
}
