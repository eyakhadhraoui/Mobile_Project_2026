import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/complaint_model.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/complaint_provider.dart';
import '../../services/user_service.dart';
import 'assistant_reclamation_screen.dart';
import 'complaint_detail_screen.dart';
import 'complaint_form_screen.dart';
import 'complaints_map_screen.dart';
import 'incident_screen.dart';

class ComplaintsScreen extends StatefulWidget {
  const ComplaintsScreen({super.key});
  @override
  State<ComplaintsScreen> createState() => _ComplaintsScreenState();
}

class _ComplaintsScreenState extends State<ComplaintsScreen> with WidgetsBindingObserver {
  bool _isOwner = false;
  bool _assistantDisponible = false;
  int _filter = 0;
  Timer? _syncTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final userId = context.read<AuthProvider>().currentUserId;
      if (userId == null) return;
      final user = await UserService().getById(userId);
      if (!mounted) return;
      _isOwner = user?.rolePrincipal == UserRole.proprietaire || user?.rolePrincipal == UserRole.administrateur;
      _assistantDisponible = user != null && user.rolePrincipal != UserRole.prestataire;
      setState(() {});
      final provider = context.read<ComplaintProvider>();
      provider.watchAll();
      await provider.syncNow();
      _syncTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        if (mounted) context.read<ComplaintProvider>().syncNow();
      });
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) context.read<ComplaintProvider>().syncNow();
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ComplaintProvider>();
    final all = provider.complaints;
    final currentUserId = context.watch<AuthProvider>().currentUserId;
    final visible = all.where((item) => !item.isDraft || item.userId == currentUserId);
    final visibleDraftCount = visible.where((item) => item.isDraft).length;
    final complaints = visible.where((item) => switch (_filter) {
      1 => item.status != ComplaintStatus.cloturee,
      2 => item.status == ComplaintStatus.cloturee,
      _ => true,
    }).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Réclamations'),
        actions: [
          if (_isOwner)
            IconButton(
              tooltip: 'Carte des réclamations',
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ComplaintsMapScreen())),
              icon: const Icon(Icons.map_outlined),
            ),
          IconButton.filledTonal(
            tooltip: 'Nouvelle réclamation',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ComplaintFormScreen())),
            icon: const Icon(Icons.add),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: provider.isLoading && all.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : provider.error != null && all.isEmpty
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(provider.error!, textAlign: TextAlign.center)))
              : Column(children: [
                  if (provider.pendingSyncCount > 0 || visibleDraftCount > 0)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(color: const Color(0xFFFFF5E5), borderRadius: BorderRadius.circular(14)),
                        child: Row(children: [
                          const Icon(Icons.cloud_sync_outlined, color: Color(0xFFA76A0A)),
                          const SizedBox(width: 9),
                          Expanded(child: Text([
                            if (visibleDraftCount > 0) '$visibleDraftCount brouillon(s) sur cet appareil',
                            if (provider.pendingSyncCount > 0) '${provider.pendingSyncCount} réclamation(s) en attente de synchronisation',
                          ].join(' · '), style: const TextStyle(fontSize: 11, color: Color(0xFF80550F)))),
                          IconButton(tooltip: 'Synchroniser', onPressed: () => provider.syncNow(), icon: const Icon(Icons.sync, color: Color(0xFFA76A0A))),
                        ]),
                      ),
                    ),
                  if (_assistantDisponible) const _AccesAssistant(),
                  // Incidents collectifs : réponse commune possible (propriétaire).
                  if (_isOwner && provider.incidents.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    BandeauIncidents(incidents: provider.incidents),
                  ],
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(color: const Color(0xFFE8F0FA), borderRadius: BorderRadius.circular(18)),
                      child: Row(children: List.generate(3, (index) => Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _filter = index),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            decoration: BoxDecoration(color: _filter == index ? Theme.of(context).colorScheme.primary : Colors.transparent, borderRadius: BorderRadius.circular(14), boxShadow: _filter == index ? const [BoxShadow(color: Color(0x11000000), blurRadius: 8, offset: Offset(0, 2))] : null),
                            child: Text(['Toutes', 'En cours', 'Résolues'][index], textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: _filter == index ? FontWeight.w700 : FontWeight.w500, color: _filter == index ? Colors.white : const Color(0xFF14263F))),
                          ),
                        ),
                      ))),
                    ),
                  ),
                  Expanded(child: complaints.isEmpty
                      ? const _EmptyState()
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
                          itemCount: complaints.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 12),
                          itemBuilder: (context, index) => _ComplaintTile(
                            complaint: complaints[index],
                            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ComplaintDetailScreen(complaint: complaints[index], canManageStatus: _isOwner, canEdit: complaints[index].userId == context.read<AuthProvider>().currentUserId && (!_isOwner || complaints[index].isDraft)))),
                          ),
                        )),
                ]),
    );
  }
}

class _AccesAssistant extends StatelessWidget {
  const _AccesAssistant();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(colors: [Color(0xFF0F3D75), Color(0xFF1F66B0)]),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AssistantReclamationsScreen())),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: .18), shape: BoxShape.circle),
                  child: const Icon(Icons.support_agent, color: Colors.white),
                ),
                const SizedBox(width: 12),
                const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Assistant IA réclamations', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
                  SizedBox(height: 2),
                  Text('Décrivez votre problème et recevez une solution adaptée.', style: TextStyle(fontSize: 12, color: Color(0xFFDCE8F6))),
                ])),
                const Icon(Icons.chevron_right, color: Colors.white),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _ComplaintTile extends StatelessWidget {
  const _ComplaintTile({required this.complaint, required this.onTap});
  final ComplaintModel complaint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final suffix = complaint.id.length <= 4 ? complaint.id.padLeft(4, '0') : complaint.id.substring(complaint.id.length - 4);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(17, 15, 13, 15),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              if (complaint.isDraft)
                const _SyncChip(label: 'Brouillon', icon: Icons.edit_note, color: Color(0xFF66748A))
              else
                _StatusChip(status: complaint.status),
              const SizedBox(width: 7),
              if (!complaint.isDraft && complaint.syncStatus == ComplaintSyncStatus.pending)
                const _SyncChip(label: 'À synchroniser', icon: Icons.cloud_upload_outlined, color: Color(0xFFA76A0A)),
              const Spacer(),
              Text('#REC-${complaint.createdAt.year}-$suffix', style: const TextStyle(fontSize: 10, color: Color(0xFF9AA5B4))),
            ]),
            const SizedBox(height: 11),
            Text(complaint.subject.trim().isEmpty ? 'Brouillon sans titre' : complaint.subject, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF14263F))),
            const SizedBox(height: 9),
            Row(children: [Icon(Icons.apartment_outlined, size: 15, color: Colors.blueGrey.shade500), const SizedBox(width: 7), Expanded(child: Text(complaint.locationId, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: Colors.blueGrey.shade600))), Text(_priorityName(complaint.priority), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: _priorityColor(complaint.priority)))]),
            const SizedBox(height: 10),
            Row(children: [Expanded(child: Text('Créée le ${_dateLabel(complaint.createdAt)}', style: const TextStyle(fontSize: 10, color: Color(0xFF9AA5B4)))), const Icon(Icons.chevron_right, color: Color(0xFF9AA5B4))]),
          ]),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) => Center(child: Padding(padding: const EdgeInsets.all(36), child: Column(mainAxisSize: MainAxisSize.min, children: [
    Icon(Icons.assignment_outlined, size: 62, color: Theme.of(context).colorScheme.primary),
    const SizedBox(height: 15),
    const Text('Aucune réclamation', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
    const SizedBox(height: 8),
    const Text('Créez une demande pour signaler un problème dans votre logement.', textAlign: TextAlign.center),
  ])));
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final ComplaintStatus status;
  @override
  Widget build(BuildContext context) {
    final color = complaintStatusColor(context, status);
    return Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(20)), child: Text(complaintStatusLabel(status), style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700)));
  }
}

class _SyncChip extends StatelessWidget {
  const _SyncChip({required this.label, required this.icon, required this.color});
  final String label;
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(color: color.withValues(alpha: .11), borderRadius: BorderRadius.circular(20)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 12, color: color), const SizedBox(width: 4), Text(label, style: TextStyle(fontSize: 9, color: color, fontWeight: FontWeight.w700))]),
  );
}

String complaintStatusLabel(ComplaintStatus status) => switch (status) { ComplaintStatus.ouverte => 'En attente', ComplaintStatus.enCours => 'En cours', ComplaintStatus.cloturee => 'Résolue' };
Color complaintStatusColor(BuildContext context, ComplaintStatus status) => switch (status) { ComplaintStatus.ouverte => const Color(0xFFE39A34), ComplaintStatus.enCours => Theme.of(context).colorScheme.primary, ComplaintStatus.cloturee => const Color(0xFF53B47D) };
String complaintCategoryLabel(ComplaintCategory category) => switch (category) {
  ComplaintCategory.bruit => 'Bruit', ComplaintCategory.panne => 'Panne', ComplaintCategory.loyer => 'Loyer', ComplaintCategory.voisinage => 'Voisinage', ComplaintCategory.autre => 'Autre', ComplaintCategory.fuiteEau => 'Fuite d’eau', ComplaintCategory.electricite => 'Électricité', ComplaintCategory.chauffage => 'Chauffage', ComplaintCategory.equipement => 'Équipement endommagé', ComplaintCategory.proprietaire => 'Problème propriétaire',
};
IconData complaintCategoryIcon(ComplaintCategory category) => switch (category) {
  ComplaintCategory.bruit => Icons.volume_up_outlined, ComplaintCategory.panne => Icons.build_outlined, ComplaintCategory.loyer => Icons.payments_outlined, ComplaintCategory.voisinage => Icons.people_outline, ComplaintCategory.autre => Icons.help_outline, ComplaintCategory.fuiteEau => Icons.water_drop_outlined, ComplaintCategory.electricite => Icons.bolt_outlined, ComplaintCategory.chauffage => Icons.ac_unit, ComplaintCategory.equipement => Icons.handyman_outlined, ComplaintCategory.proprietaire => Icons.person_outline,
};
String _priorityName(ComplaintPriority priority) => switch (priority) { ComplaintPriority.faible => 'Priorité faible', ComplaintPriority.moyenne => 'Priorité moyenne', ComplaintPriority.urgente => 'Priorité urgente' };
Color _priorityColor(ComplaintPriority priority) => switch (priority) { ComplaintPriority.faible => const Color(0xFF53A977), ComplaintPriority.moyenne => const Color(0xFFDD9132), ComplaintPriority.urgente => const Color(0xFFD75B4B) };
String _dateLabel(DateTime date) => '${date.day} ${const ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'][date.month - 1]} ${date.year}';
