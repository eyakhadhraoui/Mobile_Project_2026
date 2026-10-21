import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/complaint_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/complaint_provider.dart';
import 'complaint_form_screen.dart';
import 'complaints_screen.dart';

class ComplaintDetailScreen extends StatefulWidget {
  const ComplaintDetailScreen({super.key, required this.complaint, this.canManageStatus = false});
  final ComplaintModel complaint;
  final bool canManageStatus;
  @override
  State<ComplaintDetailScreen> createState() => _ComplaintDetailScreenState();
}

class _ComplaintDetailScreenState extends State<ComplaintDetailScreen> {
  late ComplaintModel _complaint;
  @override
  void initState() { super.initState(); _complaint = widget.complaint; }

  String get _reference {
    final suffix = _complaint.id.length <= 4 ? _complaint.id.padLeft(4, '0') : _complaint.id.substring(_complaint.id.length - 4);
    return '#${_complaint.createdAt.year}-$suffix';
  }

  @override
  Widget build(BuildContext context) {
    final history = [..._complaint.history]..sort((a, b) => b.date.compareTo(a.date));
    return Scaffold(
      appBar: AppBar(
        title: Text('Réclamation $_reference'),
        actions: [if (!widget.canManageStatus) PopupMenuButton<String>(onSelected: (value) { if (value == 'edit') { Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ComplaintFormScreen(complaint: _complaint))).then((_) => _refresh()); } else if (value == 'delete') { _confirmDelete(); } }, itemBuilder: (_) => const [PopupMenuItem(value: 'edit', child: Text('Modifier')), PopupMenuItem(value: 'delete', child: Text('Supprimer'))])],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(18, 18, 18, 30), children: [
        Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [_StatusChip(status: _complaint.status), const Spacer(), Text(_reference, style: const TextStyle(fontSize: 11, color: Color(0xFF8193AA)))]),
          const SizedBox(height: 13),
          Text(_complaint.subject, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600, color: Color(0xFF172B45))),
          const SizedBox(height: 8),
          Text('${_complaint.locationId} · ${complaintPriorityLabel(_complaint.priority)}', style: const TextStyle(fontSize: 12, color: Color(0xFF647995))),
        ]))),
        const SizedBox(height: 28),
        const Text('Suivi de la demande', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF172B45))),
        const SizedBox(height: 13),
        if (widget.canManageStatus) Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: _chooseStatus, icon: const Icon(Icons.edit_note), label: const Text('Mettre à jour le statut'))),
        ...history.asMap().entries.map((entry) => _TimelineItem(entry: entry.value, isLatest: entry.key == 0, isLast: entry.key == history.length - 1)),
        const SizedBox(height: 15),
        _InfoPanel(icon: Icons.apartment_outlined, title: 'Logement', body: _complaint.locationId),
        const SizedBox(height: 12),
        _InfoPanel(icon: complaintCategoryIcon(_complaint.category), title: complaintCategoryLabel(_complaint.category), body: _complaint.description),
        if (_complaint.photos.isNotEmpty) ...[
          const SizedBox(height: 22),
          const Text('Photos jointes', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          SizedBox(height: 116, child: ListView.separated(scrollDirection: Axis.horizontal, itemCount: _complaint.photos.length, separatorBuilder: (_, _) => const SizedBox(width: 10), itemBuilder: (_, index) => ClipRRect(borderRadius: BorderRadius.circular(14), child: Image.file(File(_complaint.photos[index]), width: 116, fit: BoxFit.cover)))),
        ],
      ]),
    );
  }

  void _refresh() async {
    final updated = await context.read<ComplaintProvider>().complaintById(_complaint.id);
    if (mounted && updated != null) setState(() => _complaint = updated);
  }

  Future<void> _chooseStatus() async {
    final selected = await showModalBottomSheet<ComplaintStatus>(context: context, builder: (context) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: ComplaintStatus.values.map((status) => ListTile(title: Text(complaintStatusLabel(status)), trailing: status == _complaint.status ? const Icon(Icons.check) : null, onTap: () => Navigator.pop(context, status))).toList())));
    if (selected == null || selected == _complaint.status || !mounted) return;
    await context.read<ComplaintProvider>().updateStatus(_complaint.id, selected);
    if (!mounted) return;
    setState(() => _complaint = ComplaintModel(id: _complaint.id, userId: _complaint.userId, locationId: _complaint.locationId, subject: _complaint.subject, category: _complaint.category, description: _complaint.description, photos: _complaint.photos, status: selected, priority: _complaint.priority, createdAt: _complaint.createdAt, history: [..._complaint.history, ComplaintHistoryEntry(status: selected, date: DateTime.now())]));
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(title: const Text('Supprimer la réclamation ?'), content: const Text('Cette action supprimera aussi son historique.'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Supprimer'))]));
    if (confirmed != true || !mounted) return;
    final userId = context.read<AuthProvider>().currentUserId;
    if (userId == null) return;
    await context.read<ComplaintProvider>().delete(_complaint.id, userId: userId);
    if (mounted) Navigator.of(context).pop();
  }
}

class _TimelineItem extends StatelessWidget {
  const _TimelineItem({required this.entry, required this.isLatest, required this.isLast});
  final ComplaintHistoryEntry entry;
  final bool isLatest;
  final bool isLast;
  @override
  Widget build(BuildContext context) {
    final color = complaintStatusColor(context, entry.status);
    return IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(width: 43, child: Column(children: [Container(width: 32, height: 32, decoration: BoxDecoration(shape: BoxShape.circle, color: isLatest ? color : const Color(0xFFEAF1F6), border: Border.all(color: isLatest ? color : const Color(0xFFDCE7F1))), child: Icon(isLatest ? Icons.check : Icons.circle, size: isLatest ? 18 : 12, color: isLatest ? Colors.white : const Color(0xFF90A4B8))), if (!isLast) Expanded(child: Container(width: 1, color: const Color(0xFFD6E4F0)))])),
      Expanded(child: Padding(padding: const EdgeInsets.only(left: 5, top: 1, bottom: 20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(complaintStatusLabel(entry.status), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF172B45))), const SizedBox(height: 5), Text(_statusDescription(entry.status), style: const TextStyle(fontSize: 11, color: Color(0xFF647995))), const SizedBox(height: 5), Text(_dateLabel(entry.date), style: const TextStyle(fontSize: 10, color: Color(0xFF8AA0B8)))]))),
    ]));
  }
}

class _InfoPanel extends StatelessWidget {
  const _InfoPanel({required this.icon, required this.title, required this.body});
  final IconData icon;
  final String title;
  final String body;
  @override
  Widget build(BuildContext context) => Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [Icon(icon, size: 19, color: Theme.of(context).colorScheme.primary), const SizedBox(width: 9), Text(title, style: const TextStyle(fontWeight: FontWeight.w700))]), const SizedBox(height: 10), Text(body, style: const TextStyle(height: 1.45, color: Color(0xFF526981)))])));
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final ComplaintStatus status;
  @override
  Widget build(BuildContext context) { final color = complaintStatusColor(context, status); return Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(20)), child: Text(complaintStatusLabel(status), style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700))); }
}

String _statusDescription(ComplaintStatus status) => switch (status) { ComplaintStatus.ouverte => 'Votre demande a bien été enregistrée.', ComplaintStatus.enCours => 'La demande est en cours de traitement.', ComplaintStatus.cloturee => 'La demande a été marquée comme résolue.' };
String _dateLabel(DateTime date) => '${date.day} ${const ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'][date.month - 1]} · ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
String complaintPriorityLabel(ComplaintPriority priority) => switch (priority) { ComplaintPriority.faible => 'Priorité faible', ComplaintPriority.moyenne => 'Priorité moyenne', ComplaintPriority.urgente => 'Priorité urgente' };
