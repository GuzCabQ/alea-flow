// ignore_for_file: uri_does_not_exist
import 'package:get_it/get_it.dart';
import '../auth/auth_repository.dart';
import '../auth/auth_service.dart';

void configureDependencies() {
  final getIt = GetIt.instance;
  getIt.registerSingleton<AuthService>(AuthService());
  getIt.registerSingleton<AuthRepository>(AuthRepositoryImpl());
}
