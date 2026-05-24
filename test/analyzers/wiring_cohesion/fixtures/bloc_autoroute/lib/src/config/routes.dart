// ignore_for_file: uri_does_not_exist
import 'package:auto_route/auto_route.dart';
import '../../profile/profile_screen.dart';

@AutoRouterConfig()
class AppRouter {
  static final routes = [AutoRoute(page: ProfileScreen)];
}
