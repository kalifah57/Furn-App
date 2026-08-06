import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/router/app_router.dart';
import 'flow_controller.dart';

/// شاشة رفع الصور (تجريبية — تستخدم Vision وهميًا في الـ MVP).
class ImageInputScreen extends ConsumerStatefulWidget {
  const ImageInputScreen({super.key});

  @override
  ConsumerState<ImageInputScreen> createState() => _ImageInputScreenState();
}

class _ImageInputScreenState extends ConsumerState<ImageInputScreen> {
  final _refs = <String>[];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.imageTitle)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(AppStrings.imageHint, style: theme.textTheme.bodyLarge),
              const SizedBox(height: 16),
              Expanded(
                child: _refs.isEmpty
                    ? Center(
                        child: Text('لا صور بعد',
                            style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant)),
                      )
                    : GridView.count(
                        crossAxisCount: 3,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        children: [
                          for (final _ in _refs)
                            Container(
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.image_outlined, size: 40),
                            ),
                        ],
                      ),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: const Text(AppStrings.addSampleImage),
                onPressed: () => setState(
                    () => _refs.add('mock_image_${_refs.length + 1}')),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _refs.isEmpty
                    ? null
                    : () {
                        ref
                            .read(furnishingFlowControllerProvider.notifier)
                            .runImages(_refs);
                        context.go(Routes.assistantThinking);
                      },
                child: const Text(AppStrings.analyzeRequest),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
