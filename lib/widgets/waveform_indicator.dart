import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

class WaveformIndicator extends StatefulWidget {
  const WaveformIndicator({super.key, required this.active});

  final bool active;

  @override
  State<WaveformIndicator> createState() => _WaveformIndicatorState();
}

class _WaveformIndicatorState extends State<WaveformIndicator> {
  final Random _rand = Random();
  late List<double> _heights;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _heights = List.generate(5, (_) => 6.0);
    _toggle();
  }

  @override
  void didUpdateWidget(covariant WaveformIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) {
      _toggle();
    }
  }

  void _toggle() {
    _timer?.cancel();
    if (widget.active) {
      _timer = Timer.periodic(const Duration(milliseconds: 120), (_) {
        setState(() {
          _heights = List.generate(5, (_) => 6 + _rand.nextDouble() * 18);
        });
      });
    } else {
      setState(() {
        _heights = List.generate(5, (_) => 6.0);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: _heights
          .map(
            (height) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: 4,
                height: height,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}
