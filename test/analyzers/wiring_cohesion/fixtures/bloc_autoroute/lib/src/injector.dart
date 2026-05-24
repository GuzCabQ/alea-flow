// ignore_for_file: uri_does_not_exist
import 'package:get_it/get_it.dart';
import '../profile/profile_service.dart';

final getIt = GetIt.instance;

void setupInjection() {
  getIt.registerLazySingleton<ProfileService>(() => ProfileService());
}
