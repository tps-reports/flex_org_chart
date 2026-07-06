import 'package:flutter/material.dart';

/// Default expand/collapse affordance rendered under a node that has
/// children. Shows the direct-subordinate count and toggles [onTap].
class DefaultExpandButton extends StatelessWidget {
  const DefaultExpandButton({
    super.key,
    required this.expanded,
    required this.count,
    required this.onTap,
  });

  final bool expanded;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      shape: const StadiumBorder(),
      color: Theme.of(context).colorScheme.surface,
      elevation: 1,
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(expanded ? Icons.expand_less : Icons.expand_more, size: 16),
              Text('$count', style: Theme.of(context).textTheme.labelSmall),
            ],
          ),
        ),
      ),
    );
  }
}
