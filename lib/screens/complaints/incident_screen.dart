import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/complaint_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/complaint_provider.dart';
import '../../providers/user_provider.dart';
import '../../services/incident_service.dart';
import 'complaint_detail_screen.dart';
import 'complaints_screen.dart';

/// Incident collectif (vue propriétaire) : les signalements regroupés et une
/// réponse unique envoyée à tous les étudiants concernés.
class IncidentScreen extends StatefulWidget {
  const IncidentScreen({super.key, required this.incidentId});

  /// Identifiant du premier signalement (l'incident est recalculé en direct).
  final String incidentId;

  @override
  State<IncidentScreen> createState() => _IncidentScreenState();
}

class _IncidentScreenState extends State<IncidentScreen> {
  final _message = TextEditingController();
  ComplaintStatus? _statut = ComplaintStatus.enCours;
  bool _envoi = false;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _envoyer(IncidentCollectif incident) async {
    final texte = _message.text.trim();
    if (texte.isEmpty || _envoi) return;
    final auteurId = context.read<AuthProvider>().currentUserId;
    if (auteurId == null) return;
    final langue = context.read<UserProvider>().user?.langue ?? 'fr';
    final provider = context.read<ComplaintProvider>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Réponse commune'),
        content: Text(
          'Ce message sera ajouté aux ${incident.reclamations.length} réclamations '
          '(${incident.nombreEtudiants} étudiant(s))'
          '${_statut == null ? '' : ', qui passeront au statut « ${complaintStatusLabel(_statut!)} »'}.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Envoyer à tous')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _envoi = true);
    try {
      await provider.repondreIncident(incident, texte: texte, auteurId: auteurId, langue: langue, statut: _statut);
      if (!mounted) return;
      _message.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Réponse envoyée à ${incident.nombreEtudiants} étudiant(s).')),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Réponse non enregistrée.')));
      }
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ComplaintProvider>();
    final incident = provider.incidents.where((i) => i.id == widget.incidentId).firstOrNull;
    if (incident == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Incident collectif')),
        body: const Center(child: Text('Cet incident est résolu ou ne regroupe plus plusieurs signalements.')),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Incident collectif')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(complaintCategoryIcon(incident.categorie), color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(complaintCategoryLabel(incident.categorie), style: const TextStyle(fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(incident.batiment, style: const TextStyle(fontSize: 16, color: Color(0xFF172B45))),
                  const SizedBox(height: 6),
                  Text(
                    '${incident.reclamations.length} signalements · ${incident.nombreEtudiants} étudiant(s) · '
                    'du ${_jour(incident.debut)} au ${_jour(incident.fin)}',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF647995)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Signalements', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          for (final reclamation in incident.reclamations)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(reclamation.subject, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('${complaintStatusLabel(reclamation.status)} · ${reclamation.locationId} · ${_jour(reclamation.createdAt)}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ComplaintDetailScreen(complaint: reclamation, canManageStatus: true, canEdit: false),
                ),
              ),
            ),
          const SizedBox(height: 16),
          const Text('Réponse commune', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 4),
          const Text(
            'Chaque étudiant la reçoit dans les échanges de sa réclamation (et peut la traduire).',
            style: TextStyle(fontSize: 12, color: Color(0xFF647995)),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _message,
            minLines: 3,
            maxLines: 6,
            maxLength: 4000,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(hintText: 'Ex. : Le plombier intervient demain à 9 h dans tout le bloc.'),
          ),
          DropdownButtonFormField<ComplaintStatus?>(
            initialValue: _statut,
            decoration: const InputDecoration(labelText: 'Statut des réclamations'),
            items: [
              const DropdownMenuItem(value: null, child: Text('Ne pas changer')),
              for (final statut in ComplaintStatus.values)
                DropdownMenuItem(value: statut, child: Text(complaintStatusLabel(statut))),
            ],
            onChanged: (valeur) => setState(() => _statut = valeur),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _envoi ? null : () => _envoyer(incident),
            icon: _envoi
                ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.campaign_outlined),
            label: Text('Envoyer aux ${incident.nombreEtudiants} étudiant(s)'),
          ),
        ],
      ),
    );
  }
}

String _jour(DateTime date) {
  final d = date.toLocal();
  String deux(int v) => v.toString().padLeft(2, '0');
  return '${deux(d.day)}/${deux(d.month)} ${deux(d.hour)}h${deux(d.minute)}';
}

/// Bandeau des incidents collectifs en tête de la liste des réclamations (propriétaire).
class BandeauIncidents extends StatelessWidget {
  const BandeauIncidents({super.key, required this.incidents});
  final List<IncidentCollectif> incidents;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 92,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      itemCount: incidents.length,
      separatorBuilder: (_, _) => const SizedBox(width: 10),
      itemBuilder: (context, index) {
        final incident = incidents[index];
        return InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => IncidentScreen(incidentId: incident.id)),
          ),
          child: Container(
            width: 240,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFFFFEEE9), borderRadius: BorderRadius.circular(16)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.groups_outlined, size: 18, color: Color(0xFFB2432C)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Incident collectif · ${incident.reclamations.length} signalements',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFFB2432C)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(complaintCategoryLabel(incident.categorie), style: const TextStyle(fontSize: 12)),
                Text(incident.batiment, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Color(0xFF647995))),
              ],
            ),
          ),
        );
      },
    ),
  );
}
