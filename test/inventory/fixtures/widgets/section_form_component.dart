// ignore_for_file: uri_does_not_exist, undefined_class
// Multiple public classes in one file — the inventory captures both.

import 'package:flutter/material.dart';

class SectionFormComponent extends StatelessWidget {
  final List<Widget> children;
  const SectionFormComponent({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(children: children);
  }
}

class SectionDividerWidget extends StatelessWidget {
  const SectionDividerWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Divider(color: StyleColors.brand40);
  }
}
