import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import 'skeleton.dart';

/// Full-page loading placeholder — skeleton layout instead of a spinner.
class AppLoadingView extends StatelessWidget {
  const AppLoadingView({
    super.key,
    this.message,
    this.itemCount = 4,
    this.padding,
  });

  final String? message;
  final int itemCount;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (message != null) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              0,
            ),
            child: Text(
              message!,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        Expanded(
          child: SkeletonList(
            itemCount: itemCount,
            padding: padding ?? const EdgeInsets.all(AppSpacing.lg),
          ),
        ),
      ],
    );
  }
}
