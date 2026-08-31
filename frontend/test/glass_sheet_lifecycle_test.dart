import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcare/shared/widgets/glass_sheet.dart';

/// Every sheet in the app is opened as `await GlassSheet.show(...)` and the
/// controllers it was handed are disposed on the line after. That is only safe
/// if the panel is off the tree by then.
///
/// It was not. `Navigator.push` resolves the instant a route is popped, while
/// the panel is still on screen playing its 240ms exit — and still rebuilding,
/// because the sheet lays out inside a `LayoutBuilder`. A rebuild that touched
/// a just-disposed `TextEditingController` threw mid-layout, and the failure
/// cascaded into the Overlay coming down with
/// `'_dependents.isEmpty': is not true` — the full-screen red error the admin
/// care board showed on "Approve & assign".
void main() {
  testWidgets('a sheet is off the tree before the caller resumes', (
    tester,
  ) async {
    var closedBeforeResume = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                await GlassSheet.show<void>(
                  context,
                  title: 'Review care request',
                  child: Builder(
                    builder: (sheetContext) => TextButton(
                      onPressed: () =>
                          Navigator.of(sheetContext, rootNavigator: true).pop(),
                      child: const Text('submit'),
                    ),
                  ),
                );
                closedBeforeResume = find
                    .text('Review care request')
                    .evaluate()
                    .isEmpty;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('submit'));
    await tester.pumpAndSettle();

    expect(
      closedBeforeResume,
      isTrue,
      reason: 'the caller must not resume while the panel is still building',
    );
  });

  testWidgets('the popped result still reaches the caller', (tester) async {
    String? result = 'unset';

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await GlassSheet.show<String>(
                  context,
                  title: 'Pick one',
                  child: Builder(
                    builder: (sheetContext) => TextButton(
                      onPressed: () => Navigator.of(
                        sheetContext,
                        rootNavigator: true,
                      ).pop('chosen'),
                      child: const Text('choose'),
                    ),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('choose'));
    await tester.pumpAndSettle();

    expect(result, 'chosen');
  });

  testWidgets('disposing the sheet controllers on return does not throw', (
    tester,
  ) async {
    await tester.pumpWidget(MaterialApp(home: _DecisionPage()));

    await tester.tap(find.textContaining('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('submit'));
    await tester.pump();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('open 0'), findsOneWidget);
  });
}

/// The shape of `AdminCareRequestsView._openReviewSheet`: page-owned
/// controllers handed to a sheet, a decision that pops, and the request that
/// follows once the sheet has closed.
class _DecisionPage extends StatefulWidget {
  @override
  State<_DecisionPage> createState() => _DecisionPageState();
}

class _DecisionPageState extends State<_DecisionPage> {
  final Set<String> _busy = {};

  Future<void> _decide() async {
    setState(() => _busy.add('r1'));
    try {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    } finally {
      if (mounted) setState(() => _busy.remove('r1'));
    }
  }

  Future<void> _openSheet(BuildContext pageContext) async {
    final note = TextEditingController();
    var decided = false;

    await GlassSheet.show<void>(
      pageContext,
      title: 'Review care request',
      child: StatefulBuilder(
        builder: (sheetContext, setSheet) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: note),
            TextButton(
              onPressed: () {
                decided = true;
                Navigator.of(sheetContext, rootNavigator: true).pop();
              },
              child: const Text('submit'),
            ),
          ],
        ),
      ),
    );

    note.dispose();
    if (decided && mounted) await _decide();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: TextButton(
        onPressed: () => _openSheet(context),
        child: Text('open ${_busy.length}'),
      ),
    ),
  );
}
