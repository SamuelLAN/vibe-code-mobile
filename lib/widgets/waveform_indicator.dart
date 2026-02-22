import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

class WaveformIndicator extends StatefulWidget {
  const WaveformIndicator({super.key, required this.active, this.color});

  final bool active;
  final Color? color;

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
    _heights = List.generate(40, (_) => 4.0);
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
      _timer = Timer.periodic(const Duration(milliseconds: 60), (_) {
        if (mounted) {
          setState(() {
            // Create a more continuous wave look
            _heights = List.generate(40, (i) {
              final val = 4 + _rand.nextDouble() * 24;
              return val;
            });
          });
        }
      });
    } else {
      if (mounted) {
        setState(() {
          _heights = List.generate(40, (_) => 4.0);
        });
      }
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
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: _heights
          .map(
            (height) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1.0),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 60),
                width: 2.5,
                height: height,
                decoration: BoxDecoration(
                  color: widget.color ?? Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}
