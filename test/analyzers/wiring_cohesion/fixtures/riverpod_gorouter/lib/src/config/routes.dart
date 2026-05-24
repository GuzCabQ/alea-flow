// ignore_for_file: uri_does_not_exist
import 'package:go_router/go_router.dart';
import '../../auth/login_screen.dart';

final router = GoRouter(
  routes: [
    GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
  ],
);
