import 'package:flutter/material.dart';

import 'l10n.dart';

/// Keep a form's fields mounted so validation can locate off-screen inputs.
class CloudForm extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final List<Widget> children;
  const CloudForm({super.key, required this.formKey, required this.children});

  @override
  Widget build(BuildContext context) => Form(
    key: formKey,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    ),
  );
}

bool validateCloudForm(GlobalKey<FormState> key) {
  final invalid = key.currentState!.validateGranularly();
  if (invalid.isEmpty) return true;
  final target = invalid.first;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (target.mounted) {
      Scrollable.ensureVisible(target.context, alignment: .15);
    }
  });
  return false;
}

/// Validation for grouped choices and counts, alongside ordinary input fields.
class CloudValidation extends StatelessWidget {
  final String? Function() validate;
  final Widget child;
  const CloudValidation({
    super.key,
    required this.validate,
    required this.child,
  });

  @override
  Widget build(BuildContext context) => FormField<void>(
    validator: (_) => validate(),
    builder: (state) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        child,
        if (state.hasError)
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 8),
            child: Semantics(
              liveRegion: true,
              child: Text(
                tr(context, state.errorText!),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ),
      ],
    ),
  );
}
