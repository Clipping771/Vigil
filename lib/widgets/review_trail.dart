import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/exception_record.dart';
import 'app_shell.dart';

/// "Resolved by Olivia Owner · 29 Oct, 3:10 PM" plus the reviewer's note.
class ReviewTrail extends StatelessWidget {
  final ExceptionRecord ex;
  const ReviewTrail(this.ex, {super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final when = ex.reviewedAt ?? ex.resolvedAt;
    final who = ex.reviewedByName;
    final hasNote = ex.resolutionNote != null && ex.resolutionNote!.trim().isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          who != null ? UserAvatar(name: who, radius: 14) : Icon(Icons.history, size: 20, color: cs.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(children: [
                    TextSpan(text: '${ex.reviewVerb} by ', style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                    TextSpan(text: who ?? 'the system', style: t.labelLarge),
                    if (when != null)
                      TextSpan(
                        text: '  ·  ${DateFormat('d MMM, h:mm a').format(when.toLocal())}',
                        style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                  ]),
                ),
                if (hasNote) ...[
                  const SizedBox(height: 4),
                  Text('“${ex.resolutionNote!.trim()}”', style: t.bodyMedium),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
