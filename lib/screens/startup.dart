import '../l10n.dart';
import 'package:flutter/material.dart';
import '../ui.dart';

class StartupPage extends StatelessWidget {
  const StartupPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final theme = Theme.of(context);
    final reduced =
        store.reduceMotion || MediaQuery.disableAnimationsOf(context);
    return Scaffold(
      body: Backdrop(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 40,
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const BrandMark(size: 60),
                          const SizedBox(height: 28),
                          Text(
                            'LINESIGHT',
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: theme.colorScheme.primary,
                              letterSpacing: 2,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            tr(context, "正在打开\n本机工作区"),
                            style: theme.textTheme.headlineLarge,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            tr(context, "记录较多时可能需要稍候。准备完成后即可登录。"),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              height: 1.6,
                            ),
                          ),
                          const SizedBox(height: 28),
                          GlassPanel(
                            child: Row(
                              children: [
                                ExcludeSemantics(
                                  child: SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: reduced
                                        ? Icon(
                                            Icons.hourglass_top_rounded,
                                            size: 22,
                                            color: theme.colorScheme.primary,
                                          )
                                        : const CircularProgressIndicator(
                                            strokeWidth: 2.5,
                                          ),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Semantics(
                                    liveRegion: true,
                                    child: Text(
                                      trMessage(context, store.startupStage),
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 28),
                          Text(
                            tr(context, "LineSight {0} · 质量工作台", [appVersion]),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
