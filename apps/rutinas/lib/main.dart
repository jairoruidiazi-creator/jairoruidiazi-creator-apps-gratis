import 'package:flutter/material.dart';

// Entrada mínima mientras el flujo "Bootstrap de plataformas" genera android/
// e ios/; la app completa llega en el siguiente commit.
void main() => runApp(const MaterialApp(title: 'Rutinas', home: Scaffold(body: Center(child: Text('Rutinas')))));
