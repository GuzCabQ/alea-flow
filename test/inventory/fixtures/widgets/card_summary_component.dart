// ignore_for_file: uri_does_not_exist, undefined_class
import 'package:flutter/material.dart';

class CardSummaryComponent extends StatelessWidget {
  final String title;
  final String subtitle;

  const CardSummaryComponent({
    super.key,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: StyleColors.brand20,
      padding: EdgeInsets.all(StyleSize.md),
      child: Column(
        children: [
          Text(title, style: StyleFonts.title),
          Text(subtitle, style: StyleFonts.body1),
        ],
      ),
    );
  }
}
