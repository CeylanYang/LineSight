import 'package:flutter/material.dart';

void main() => runApp(const LineSightApp());

const brandBlue = Color(0xFF3083FF);
const brandGreen = Color(0xFF12C77A);
const danger = Color(0xFFFF5964);
const muted = Color(0xFF929AAF);
const canvas = Color(0xFFF8FAFD);

class LineSightApp extends StatefulWidget {
  const LineSightApp({super.key});

  @override
  State<LineSightApp> createState() => _LineSightAppState();
}

class _LineSightAppState extends State<LineSightApp> {
  int _tab = 0;
  bool _dark = false;
  String _language = 'English';

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: brandBlue,
      brightness: _dark ? Brightness.dark : Brightness.light,
    );
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'LineSight',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: _dark ? const Color(0xFF11141B) : canvas,
        fontFamily: 'Roboto',
        appBarTheme: AppBarTheme(
          backgroundColor: _dark ? const Color(0xFF11141B) : canvas,
          surfaceTintColor: Colors.transparent,
        ),
      ),
      home: Scaffold(
        body: SafeArea(
          bottom: false,
          child: IndexedStack(
            index: _tab,
            children: [
              const HomePage(),
              const ModulesPage(),
              const InspectionPage(),
              ProfilePage(
                dark: _dark,
                language: _language,
                onDarkChanged: (v) => setState(() => _dark = v),
                onLanguageChanged: (v) => setState(() => _language = v),
              ),
            ],
          ),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (index) => setState(() => _tab = index),
          backgroundColor: _dark ? const Color(0xFF1A1F29) : Colors.white,
          indicatorColor: brandBlue.withValues(alpha: .10),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.camera_alt_outlined), selectedIcon: Icon(Icons.camera_alt), label: 'Home'),
            NavigationDestination(icon: Icon(Icons.grid_view_rounded), selectedIcon: Icon(Icons.grid_view_rounded), label: 'Modules'),
            NavigationDestination(icon: Icon(Icons.view_in_ar_outlined), selectedIcon: Icon(Icons.view_in_ar), label: 'PR'),
            NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profile'),
          ],
        ),
      ),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final stations = [
      ('LINE-03 Station-01', '96.4%', '1249', true),
      ('LINE-03 Station-02', '93.1%', '982', false),
      ('LINE-03 Station-03', '97.8%', '1103', true),
      ('LINE-03 Station-04', '98.2%', '1322', true),
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
      children: [
        Row(children: [
          const Icon(Icons.camera_alt, color: brandBlue, size: 29),
          const SizedBox(width: 9),
          Expanded(child: Text('LineSight · Home', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700))),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('2026-09-16 14:31', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: muted)),
            const SizedBox(height: 5),
            const StatusPill(label: 'All synced', color: brandGreen, soft: Color(0xFFE7F8F0)),
          ]),
        ]),
        const SizedBox(height: 20),
        Card(child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Opening defect alerts'))),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 18, vertical: 19),
            child: Row(children: [
              Icon(Icons.warning_amber_rounded, color: Color(0xFFFF9800), size: 28),
              SizedBox(width: 12),
              Expanded(child: Text('3 defect alerts to confirm', style: TextStyle(color: danger, fontSize: 17, fontWeight: FontWeight.w600))),
              Icon(Icons.chevron_right, color: danger),
            ]),
          ),
        )),
        const SizedBox(height: 14),
        ...stations.map((s) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: StationCard(name: s.$1, yield: s.$2, inspected: s.$3, pass: s.$4),
        )),
        Row(children: [
          Expanded(child: QuickLink(icon: Icons.assignment_outlined, title: 'History', subtitle: 'Inspection records', color: brandGreen)),
          const SizedBox(width: 12),
          Expanded(child: QuickLink(icon: Icons.bar_chart_rounded, title: 'Statistics', subtitle: 'Quality dashboard', color: brandBlue)),
        ]),
      ],
    );
  }
}

class StationCard extends StatelessWidget {
  const StationCard({super.key, required this.name, required this.yield, required this.inspected, required this.pass});
  final String name;
  final String yield;
  final String inspected;
  final bool pass;

  @override
  Widget build(BuildContext context) {
    final color = pass ? brandGreen : danger;
    return Card(child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 15, 14, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600))),
          StatusPill(label: pass ? 'PASS' : 'FAIL', color: pass ? const Color(0xFF15A95F) : Colors.white, soft: pass ? const Color(0xFFB8EFCE) : const Color(0xFFFF6C76)),
        ]),
        const SizedBox(height: 14),
        Text('24h yield: $yield   |   Inspected today: $inspected', style: const TextStyle(color: muted, fontSize: 14)),
        const SizedBox(height: 11),
        Row(children: [
          Icon(Icons.circle, size: 11, color: pass ? brandGreen : const Color(0xFFFF9800)),
          const SizedBox(width: 6),
          Expanded(child: Text(pass ? 'Synced' : 'Queued · 12 defects pending', style: TextStyle(color: pass ? brandGreen : const Color(0xFFFF9800), fontSize: 14))),
          const MiniYieldChart(),
          const SizedBox(width: 10),
          FilledButton.tonal(onPressed: () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Showing $name'))), child: const Text('View details')),
        ]),
      ]),
    ));
  }
}

class MiniYieldChart extends StatelessWidget {
  const MiniYieldChart({super.key});
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 52,
    height: 30,
    child: Row(crossAxisAlignment: CrossAxisAlignment.end, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: List.generate(7, (i) => Container(
      width: 5,
      height: 9 + ((i * 7 + 4) % 15).toDouble(),
      decoration: BoxDecoration(color: const Color(0xFFBFEDE5), borderRadius: BorderRadius.circular(2)),
    ))),
  );
}

class QuickLink extends StatelessWidget {
  const QuickLink({super.key, required this.icon, required this.title, required this.subtitle, required this.color});
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  @override
  Widget build(BuildContext context) => Card(child: InkWell(
    borderRadius: BorderRadius.circular(20),
    onTap: () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$title selected'))),
    child: Padding(padding: const EdgeInsets.all(12), child: Row(children: [
      Container(width: 44, height: 54, decoration: BoxDecoration(color: color.withValues(alpha: .10), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: color)),
      const SizedBox(width: 9),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 5),
        Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: muted)),
      ])),
      const Icon(Icons.chevron_right, color: Color(0xFFD8DFEA), size: 18),
    ])),
  ));
}

class ModulesPage extends StatelessWidget {
  const ModulesPage({super.key});
  @override
  Widget build(BuildContext context) {
    final recipes = [
      ('BRK-1042 v3.2', 80, 8, '0.75', true),
      ('BRK-1021 v2.8', 70, 6, '0.70', false),
      ('BRK-0987 v1.9', 65, 5, '0.65', false),
      ('BRK-0755 v1.4', 60, 4, '0.60', false),
    ];
    return ListView(padding: const EdgeInsets.fromLTRB(20, 24, 20, 24), children: [
      Row(children: [Expanded(child: Text('Modules · Recipes & System', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700))), IconButton(onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Recipes refreshed'))), icon: const Icon(Icons.refresh))]),
      const SizedBox(height: 14),
      const RecipeTabs(),
      const SizedBox(height: 20),
      ...recipes.map((r) => Padding(padding: const EdgeInsets.only(bottom: 12), child: RecipeCard(name: r.$1, sensitivity: r.$2, classes: r.$3, confidence: r.$4, active: r.$5))),
    ]);
  }
}

class RecipeTabs extends StatefulWidget {
  const RecipeTabs({super.key});
  @override
  State<RecipeTabs> createState() => _RecipeTabsState();
}
class _RecipeTabsState extends State<RecipeTabs> {
  int selected = 0;
  @override
  Widget build(BuildContext context) => Card(child: Padding(padding: const EdgeInsets.all(4), child: Row(children: ['Recipes', 'Changeovers', 'System status'].asMap().entries.map((e) => Expanded(child: InkWell(
    borderRadius: BorderRadius.circular(14), onTap: () => setState(() => selected = e.key),
    child: Container(padding: const EdgeInsets.symmetric(vertical: 14), decoration: BoxDecoration(border: Border(bottom: BorderSide(color: selected == e.key ? brandBlue : Colors.transparent, width: 2))), child: Text(e.value, textAlign: TextAlign.center, style: TextStyle(color: selected == e.key ? brandBlue : muted, fontWeight: FontWeight.w600, fontSize: 13))),
  ))).toList())));
}

class RecipeCard extends StatelessWidget {
  const RecipeCard({super.key, required this.name, required this.sensitivity, required this.classes, required this.confidence, required this.active});
  final String name;
  final int sensitivity;
  final int classes;
  final String confidence;
  final bool active;
  @override
  Widget build(BuildContext context) {
    final color = active ? brandGreen : brandBlue;
    return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 54, height: 58, decoration: BoxDecoration(color: color.withValues(alpha: .08), borderRadius: BorderRadius.circular(13)), child: Icon(Icons.view_in_ar_outlined, color: color, size: 34)),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
          if (active) ...[const SizedBox(height: 5), const Text('●  Active    Running', style: TextStyle(color: brandGreen, fontSize: 12))],
        ])),
      ]),
      const SizedBox(height: 13),
      _RecipeLine('Sensitivity: $sensitivity%'),
      _RecipeLine('Defect classes: $classes enabled'),
      Row(children: [Expanded(child: _RecipeLine('Min. confidence: $confidence')), FilledButton.tonal(onPressed: () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$name applied'))), child: const Text('Apply recipe'))]),
    ])));
  }
}
class _RecipeLine extends StatelessWidget {
  const _RecipeLine(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(left: 68, bottom: 8), child: Row(children: [const Text('•  ', style: TextStyle(color: muted)), Expanded(child: Text(label, style: const TextStyle(color: muted, fontSize: 14)))]));
}

class InspectionRecord {
  const InspectionRecord(this.time, this.fail, this.defect, this.confidence);
  final String time;
  final bool fail;
  final String defect;
  final String confidence;
}

class InspectionPage extends StatefulWidget {
  const InspectionPage({super.key});
  @override
  State<InspectionPage> createState() => _InspectionPageState();
}
class _InspectionPageState extends State<InspectionPage> {
  String _range = 'Today';
  String _result = 'All';
  String _defect = 'All';
  String _line = 'All';
  String _recipe = 'All';
  int _selected = 0;
  final _note = TextEditingController();
  final _records = const [
    InspectionRecord('14:31:08', true, 'Pinhole', '0.93'),
    InspectionRecord('14:28:55', false, '—', '1.00'),
    InspectionRecord('14:26:33', true, 'Crack', '0.88'),
    InspectionRecord('14:20:11', false, '—', '1.00'),
    InspectionRecord('14:18:07', true, 'Pinhole', '0.76'),
  ];
  @override
  void dispose() { _note.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final filtered = _records.asMap().entries.where((e) => (_result == 'All' || (_result == 'FAIL') == e.value.fail) && (_defect == 'All' || e.value.defect == _defect)).toList();
    final record = _records[_selected];
    return ListView(padding: const EdgeInsets.fromLTRB(16, 24, 16, 24), children: [
      Text('PR · Inspection & Review History', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
      const SizedBox(height: 18),
      _filterCard(),
      const SizedBox(height: 14),
      ...filtered.map((entry) => Padding(padding: const EdgeInsets.only(bottom: 10), child: InspectionListCard(index: entry.key, record: entry.value, selected: _selected == entry.key, onTap: () => setState(() => _selected = entry.key)))),
      const SizedBox(height: 4),
      _detailCard(record),
    ]);
  }
  Widget _filterCard() => Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(children: [
    Row(children: [Expanded(child: _dropdown('Time range', _range, ['Today', '7 days', '30 days'], (v) => setState(() => _range = v))), const SizedBox(width: 12), Expanded(child: _dropdown('Result', _result, ['All', 'FAIL', 'PASS'], (v) => setState(() => _result = v)))]),
    Row(children: [Expanded(child: _dropdown('Defect class', _defect, ['All', 'Pinhole', 'Crack'], (v) => setState(() => _defect = v))), const SizedBox(width: 12), Expanded(child: _dropdown('Line', _line, ['All', 'LINE-03'], (v) => setState(() => _line = v)))]),
    Row(children: [Expanded(child: _dropdown('Recipe', _recipe, ['All', 'BRK-1042 v3.2'], (v) => setState(() => _recipe = v))), const SizedBox(width: 12), Expanded(child: FilledButton(onPressed: () => setState(() {}), child: const Text('Search')))]),
  ])));
  Widget _dropdown(String label, String value, List<String> options, ValueChanged<String> onChanged) => Padding(padding: const EdgeInsets.only(bottom: 9), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: const TextStyle(color: muted, fontSize: 12)),
    const SizedBox(height: 4),
    DropdownButtonFormField<String>(value: value, isExpanded: true, decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 9, vertical: 9), border: OutlineInputBorder()), items: options.map((o) => DropdownMenuItem(value: o, child: Text(o, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)))).toList(), onChanged: (v) { if (v != null) onChanged(v); }),
  ]));
  Widget _detailCard(InspectionRecord record) => Card(child: Padding(padding: const EdgeInsets.all(15), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [Expanded(child: Text('Inspection detail · ${record.defect == '—' ? 'No defect' : record.defect}', style: const TextStyle(fontWeight: FontWeight.w600))), IconButton(onPressed: () {}, icon: const Icon(Icons.close, color: muted))]),
    DefectPreview(fail: record.fail, large: true),
    const SizedBox(height: 16),
    _detailRow('SN', 'AM-2026-0916-0042'), _detailRow('Time', '2026-09-16 ${record.time}'), _detailRow('Result', record.fail ? 'FAIL' : 'PASS', color: record.fail ? danger : brandGreen),
    _detailRow('Defect class', record.defect), _detailRow('Confidence', record.confidence), _detailRow('Line', 'LINE-03 Station-01'), _detailRow('Recipe', 'BRK-1042 v3.2'), _detailRow('Operator', 'OP-114'), _detailRow('Sync status', 'Queued', color: const Color(0xFFFF9800)),
    const SizedBox(height: 8),
    OutlinedButton.icon(onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('CSV report exported'))), icon: const Icon(Icons.download_outlined), label: const Text('Export CSV report'), style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(42))),
    const SizedBox(height: 8), OutlinedButton.icon(onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Changeover request created'))), icon: const Icon(Icons.download_outlined), label: const Text('Request changeover'), style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(42))),
    const SizedBox(height: 12), const Text('Review note (optional)', style: TextStyle(color: muted, fontSize: 13)), const SizedBox(height: 7),
    TextField(controller: _note, maxLength: 300, maxLines: 3, onChanged: (_) => setState(() {}), decoration: const InputDecoration(hintText: 'Enter a review note...', filled: true, border: OutlineInputBorder(), counterText: '')),
    Align(alignment: Alignment.centerRight, child: Text('${_note.text.length}/300', style: const TextStyle(color: muted, fontSize: 12))),
    const SizedBox(height: 8), SizedBox(width: double.infinity, child: FilledButton(onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Review submitted'))), child: const Text('Submit review'))),
  ])));
  Widget _detailRow(String label, String value, {Color? color}) => Padding(padding: const EdgeInsets.symmetric(vertical: 9), child: Row(children: [Expanded(child: Text(label, style: const TextStyle(color: muted, fontSize: 13))), Expanded(child: Text(value, style: TextStyle(color: color ?? const Color(0xFF596175), fontSize: 13, fontWeight: color == null ? FontWeight.normal : FontWeight.w600)))]));
}

class InspectionListCard extends StatelessWidget {
  const InspectionListCard({super.key, required this.index, required this.record, required this.selected, required this.onTap});
  final int index;
  final InspectionRecord record;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final color = record.fail ? danger : brandGreen;
    return Card(color: selected ? const Color(0xFFFFFFFF) : null, child: InkWell(borderRadius: BorderRadius.circular(18), onTap: onTap, child: IntrinsicHeight(child: Row(children: [
      Container(width: 4, decoration: BoxDecoration(color: color, borderRadius: const BorderRadius.horizontal(left: Radius.circular(8)))),
      Expanded(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('2026-09-16 ${record.time}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)), const SizedBox(height: 7),
        Row(children: [Icon(Icons.circle, size: 10, color: color), const SizedBox(width: 5), Text(record.fail ? 'FAIL' : 'PASS', style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)), const SizedBox(width: 14), Text(record.defect, style: const TextStyle(color: muted, fontSize: 13))]),
        const SizedBox(height: 7), Text('Confidence ${record.confidence}', style: const TextStyle(color: muted, fontSize: 12)),
      ]))),
      Padding(padding: const EdgeInsets.only(right: 10), child: DefectPreview(fail: record.fail)),
    ]))));
  }
}

class DefectPreview extends StatelessWidget {
  const DefectPreview({super.key, required this.fail, this.large = false});
  final bool fail;
  final bool large;
  @override
  Widget build(BuildContext context) => SizedBox(width: large ? double.infinity : 60, height: large ? 112 : 62, child: ClipRRect(borderRadius: BorderRadius.circular(9), child: CustomPaint(painter: _PreviewPainter(fail: fail), child: large ? const SizedBox.expand() : null)));
}
class _PreviewPainter extends CustomPainter {
  _PreviewPainter({required this.fail});
  final bool fail;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawColor(const Color(0xFFCDD5DA), BlendMode.src);
    final line = Paint()..strokeWidth = size.height * .075..strokeCap = StrokeCap.round;
    for (var i = 0; i < 12; i++) {
      line.color = i.isEven ? const Color(0xFFB8C3C9) : const Color(0xFFDCE2E5);
      final y = i * size.height / 11;
      canvas.drawLine(Offset(-size.width * .1, y), Offset(size.width * 1.08, y + size.height * .36), line);
      line.color = i.isEven ? const Color(0xFFE2E7E9) : const Color(0xFFB9C4CA);
      canvas.drawLine(Offset(0, y + size.height * .45), Offset(size.width, y - size.height * .22), line);
    }
    final center = Offset(size.width * .51, size.height * .51);
    if (fail) {
      final box = Rect.fromCenter(center: center, width: size.width * .25, height: size.height * .59);
      canvas.drawRect(box, Paint()..color = danger..style = PaintingStyle.stroke..strokeWidth = 1.5);
    }
    final marker = Path()..moveTo(center.dx, center.dy - 4)..lineTo(center.dx + 5, center.dy)..lineTo(center.dx, center.dy + 4)..lineTo(center.dx - 5, center.dy)..close();
    canvas.drawPath(marker, Paint()..color = fail ? const Color(0xFFBF5048) : const Color(0xFF94A4AA));
  }
  @override
  bool shouldRepaint(covariant _PreviewPainter oldDelegate) => fail != oldDelegate.fail;
}

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key, required this.dark, required this.language, required this.onDarkChanged, required this.onLanguageChanged});
  final bool dark;
  final String language;
  final ValueChanged<bool> onDarkChanged;
  final ValueChanged<String> onLanguageChanged;
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.fromLTRB(20, 24, 20, 24), children: [
    Text('Profile · User & Settings', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)), const SizedBox(height: 20),
    Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(children: [
      Row(children: [
        const CircleAvatar(radius: 31, backgroundColor: Color(0xFFEAF2FF), child: Icon(Icons.person, color: Color(0xFF7AB9FF), size: 38)), const SizedBox(width: 14),
        const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('OP-114', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)), SizedBox(height: 4), Text('Operator', style: TextStyle(color: muted))])),
        const Flexible(child: StatusPill(label: 'Quality engineer', color: Color(0xFF19B76C), soft: Color(0xFFD8F5E6))),
      ]),
    const Divider(height: 30), const Align(alignment: Alignment.centerLeft, child: Text('Permissions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600))),
      const SizedBox(height: 9), const PermissionRow('View live data'), const PermissionRow('Request changeover'), const PermissionRow('Review inspections'), const PermissionRow('Edit recipes (admin only)', allowed: false),
    ]))),
    const SizedBox(height: 14),
    Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
      Row(children: [const Expanded(child: Text('My audit log', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17))), TextButton(onPressed: () {}, child: const Text('View all ›'))]),
      const _AuditRow('2026-09-16 14:31:20', 'Changeover requested', 'SN: AM-2026-0916-0042'), const Divider(height: 12),
      const _AuditRow('2026-09-16 13:38:09', 'ACK confirmed', 'SN: AM-2026-0916-0037'), const Divider(height: 12),
      const _AuditRow('2026-09-16 11:12:11', 'Recipe edit requested', 'BRK-1042 v3.2'),
    ]))),
    const SizedBox(height: 14),
    Card(child: Padding(padding: const EdgeInsets.fromLTRB(16, 10, 12, 10), child: Column(children: [
      const Align(alignment: Alignment.centerLeft, child: Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('Settings', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)))),
      Row(children: [const Expanded(child: Text('Language')), DropdownButton<String>(value: language, underline: const SizedBox(), items: const [DropdownMenuItem(value: 'English', child: Text('English')), DropdownMenuItem(value: '中文', child: Text('中文'))], onChanged: (v) { if (v != null) onLanguageChanged(v); })]),
      Row(children: [const Expanded(child: Text('Dark mode')), Switch(value: dark, onChanged: onDarkChanged)]),
    ]))),
    const SizedBox(height: 14),
    Card(child: ListTile(leading: const Icon(Icons.lock_outline, color: danger, size: 30), title: const Text('Sign out', style: TextStyle(color: danger, fontWeight: FontWeight.w700)), subtitle: const Text('Sign out and clear local cached data', style: TextStyle(color: muted)), onTap: () => showDialog<void>(context: context, builder: (context) => AlertDialog(title: const Text('Sign out?'), content: const Text('You can sign in again at any time.'), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Sign out'))])))),
  ]);
}

class PermissionRow extends StatelessWidget {
  const PermissionRow(this.label, {super.key, this.allowed = true});
  final String label;
  final bool allowed;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(vertical: 7), child: Row(children: [Icon(allowed ? Icons.check_circle_outline : Icons.cancel_outlined, color: allowed ? brandGreen : danger, size: 21), const SizedBox(width: 12), Text(label, style: TextStyle(color: allowed ? null : muted))]));
}
class _AuditRow extends StatelessWidget {
  const _AuditRow(this.time, this.title, this.serial);
  final String time, title, serial;
  @override
  Widget build(BuildContext context) => Row(children: [Expanded(flex: 5, child: Text(time, style: const TextStyle(color: Color(0xFF777F91), fontSize: 12))), Expanded(flex: 5, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontSize: 13)), Text(serial, style: const TextStyle(color: muted, fontSize: 11))])), const Icon(Icons.chevron_right, color: muted)]);
}
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.label, required this.color, required this.soft});
  final String label;
  final Color color;
  final Color soft;
  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7), decoration: BoxDecoration(color: soft, borderRadius: BorderRadius.circular(10)), child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12)));
}
