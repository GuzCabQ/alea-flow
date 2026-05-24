// ignore_for_file: uri_does_not_exist
import 'package:get/get.dart';
import '../../home/home_screen.dart';

abstract final class AppRoutes {
  static const String home = '/home';
}

final pages = <GetPage>[
  GetPage(name: AppRoutes.home, page: () => const HomeScreen()),
];
