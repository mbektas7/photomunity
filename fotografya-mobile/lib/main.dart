import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  // Hatalı bir istek (ör. 404) sessizce tekrar denenmesin; kullanıcı "Tekrar dene" ile karar verir.
  runApp(
    ProviderScope(
      retry: (retryCount, error) => null,
      child: const FotografyaApp(),
    ),
  );
}
