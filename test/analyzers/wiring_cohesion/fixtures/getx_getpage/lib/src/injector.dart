// ignore_for_file: uri_does_not_exist
import 'package:get/get.dart';
import '../home/home_controller.dart';

void registerControllers() {
  Get.put<HomeController>(HomeController());
}
