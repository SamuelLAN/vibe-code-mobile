import 'package:flutter/material.dart';

class InfoRow extends StatelessWidget {
  final String label;
  final Widget child;

  const InfoRow({
    super.key,
    required this.label,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 13, color: Colors.grey[500]),
        ),
        child,
      ],
    );
  }
}
