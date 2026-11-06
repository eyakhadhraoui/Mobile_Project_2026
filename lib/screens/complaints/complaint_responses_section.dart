import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/langues.dart';
import '../../models/complaint_model.dart';
import '../../models/complaint_response_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/complaint_provider.dart';
import '../../providers/traduction_provider.dart';
import '../../providers/user_provider.dart';
import '../../services/traduction_service.dart';

const _ink = Color(0xFF172B45);
const _muted = Color(0xFF647995);
const _rouge = Color(0xFFC53030);

/// Échanges d'une réclamation entre l'étudiant (auteur) et le propriétaire,
/// avec traduction automatique des messages de l'autre partie.
class ComplaintResponsesSection extends StatefulWidget {
  const ComplaintResponsesSection({
    super.key,
    required this.complaint,
    required this.isOwnerViewer,
    this.traductionService,
  });

  final ComplaintModel complaint;

  /// Le lecteur a le rôle propriétaire (ou administrateur) et gère la réclamation.
  final bool isOwnerViewer;

  /// Injection pour les tests.
  final TraductionService? traductionService;

  @override
  State<ComplaintResponsesSection> createState() => _ComplaintResponsesSectionState();
}

class _ComplaintResponsesSectionState extends State<ComplaintResponsesSection> {
  final _saisie = TextEditingController();
  late final TraductionProvider _traduction;
  late final Stream<List<ComplaintResponse>> _flux;
  TraductionService? _serviceLocal;
  late final String _lecteurId;
  late final String _langue;
  late final bool _traductionAuto;
  String _dernierLot = '';
  bool _envoi = false;

  @override
  void initState() {
    super.initState();
    final user = context.read<UserProvider>().user;
    _lecteurId = context.read<AuthProvider>().currentUserId ?? '';
    _langue = user?.langue ?? langueParDefaut;
    _traductionAuto = user?.preferences['traductionAuto'] == true;
    _traduction = TraductionProvider(
      service: widget.traductionService ?? (_serviceLocal = TraductionService()),
      langueCible: _langue,
      lecteurId: _lecteurId,
    );
    _flux = context.read<ComplaintProvider>().watchResponses(widget.complaint.id);
  }

  @override
  void dispose() {
    // Annule les traductions en cours : leurs résultats seront ignorés.
    _traduction.dispose();
    _serviceLocal?.fermer();
    _saisie.dispose();
    super.dispose();
  }

  /// Rôle du lecteur dans l'échange, ou null s'il ne peut pas écrire.
  ComplaintAuthorRole? get _role {
    if (widget.complaint.userId == _lecteurId) return ComplaintAuthorRole.etudiant;
    if (widget.isOwnerViewer) return ComplaintAuthorRole.proprietaire;
    return null;
  }

  Future<void> _envoyer() async {
    final texte = _saisie.text.trim();
    final role = _role;
    if (texte.isEmpty || role == null || _envoi) return;
    setState(() => _envoi = true);
    try {
      await context.read<ComplaintProvider>().addResponse(
        complaintId: widget.complaint.id,
        authorId: _lecteurId,
        authorRole: role,
        text: texte,
        langue: _langue,
      );
      _saisie.clear();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Message non enregistré.')));
      }
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider.value(
    value: _traduction,
    child: StreamBuilder<List<ComplaintResponse>>(
      stream: _flux,
      builder: (context, snapshot) {
        final messages = snapshot.data ?? const <ComplaintResponse>[];
        _traduction.definirReponses(messages);
        _lancerTraductionAuto(messages);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Échanges', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: _ink)),
            const SizedBox(height: 10),
            if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData)
              const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator()))
            else if (messages.isEmpty)
              Text(
                widget.isOwnerViewer && _role == ComplaintAuthorRole.proprietaire
                    ? 'Aucun échange. Répondez à l’étudiant ci-dessous.'
                    : 'Aucune réponse du propriétaire pour le moment.',
                style: const TextStyle(fontSize: 12, color: _muted),
              ),
            ...messages.map((message) => _Message(message: message, estMoi: message.authorId == _lecteurId)),
            if (_role != null) ...[const SizedBox(height: 8), _champSaisie()],
          ],
        );
      },
    ),
  );

  /// Traduction automatique à l'ouverture, si activée dans le profil.
  void _lancerTraductionAuto(List<ComplaintResponse> messages) {
    if (!_traductionAuto) return;
    final lot = messages.map((m) => '${m.id}:${m.text.length}').join(',');
    if (lot == _dernierLot) return;
    _dernierLot = lot;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _traduction.traduireAutomatiquement();
    });
  }

  Widget _champSaisie() => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Expanded(
        child: TextField(
          controller: _saisie,
          minLines: 1,
          maxLines: 5,
          maxLength: 4000,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            hintText: _role == ComplaintAuthorRole.proprietaire ? 'Répondre à l’étudiant…' : 'Écrire au propriétaire…',
            counterText: '',
          ),
          onSubmitted: (_) => _envoyer(),
        ),
      ),
      const SizedBox(width: 8),
      IconButton.filled(
        tooltip: 'Envoyer',
        onPressed: _envoi ? null : _envoyer,
        icon: const Icon(Icons.send),
      ),
    ],
  );
}

class _Message extends StatelessWidget {
  const _Message({required this.message, required this.estMoi});
  final ComplaintResponse message;
  final bool estMoi;

  @override
  Widget build(BuildContext context) {
    final traduction = context.watch<TraductionProvider>();
    final etat = traduction.etat(message.id);
    final afficheTraduction = etat.etat == EtatTraduction.traduit && etat.afficherTraduction;
    final auteur = message.estDuProprietaire ? 'Propriétaire' : 'Étudiant';
    final couleur = message.estDuProprietaire ? const Color(0xFFEAF3FC) : const Color(0xFFF3F6F9);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      decoration: BoxDecoration(color: couleur, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(message.estDuProprietaire ? Icons.apartment_outlined : Icons.school_outlined, size: 16, color: _muted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${estMoi ? '$auteur (vous)' : auteur} · ${_date(message.createdAt)}'
                  '${message.updatedAt != null ? ' · modifié' : ''}'
                  '${message.syncStatus == ComplaintSyncStatus.pending ? ' · à envoyer' : ''}',
                  style: const TextStyle(fontSize: 11, color: _muted, fontWeight: FontWeight.w600),
                ),
              ),
              if (estMoi) _menu(context) else const SizedBox(height: 32),
            ],
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(
              afficheTraduction ? etat.texte! : message.text,
              style: const TextStyle(height: 1.4, color: _ink),
            ),
          ),
          if (traduction.peutTraduire(message)) _ligneTraduction(context, traduction, etat, afficheTraduction),
        ],
      ),
    );
  }

  Widget _ligneTraduction(BuildContext context, TraductionProvider traduction, TraductionMessage etat, bool afficheTraduction) {
    final langue = nomLangue(traduction.langueCible);
    return switch (etat.etat) {
      EtatTraduction.idle => Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => traduction.traduireReponse(message.id),
          icon: const Icon(Icons.translate, size: 16),
          label: Text('Traduire en $langue'),
        ),
      ),
      EtatTraduction.loading => const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            SizedBox.square(dimension: 14, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 8),
            Text('Traduction en cours…', style: TextStyle(fontSize: 12, color: _muted)),
          ],
        ),
      ),
      EtatTraduction.erreur => Row(
        children: [
          const Icon(Icons.error_outline, size: 15, color: _rouge),
          const SizedBox(width: 6),
          const Text('Traduction indisponible', style: TextStyle(fontSize: 12, color: _rouge)),
          TextButton(onPressed: () => traduction.traduireReponse(message.id), child: const Text('Réessayer')),
        ],
      ),
      EtatTraduction.traduit => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (afficheTraduction)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'Traduction automatique, le texte original fait foi',
                style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: _muted),
              ),
            ),
          TextButton.icon(
            onPressed: () => traduction.basculerAffichage(message.id),
            icon: Icon(afficheTraduction ? Icons.notes : Icons.translate, size: 16),
            label: Text(afficheTraduction ? 'Voir l’original (${nomLangue(message.langue)})' : 'Voir la traduction'),
          ),
        ],
      ),
    };
  }

  Widget _menu(BuildContext context) => PopupMenuButton<String>(
    tooltip: 'Options du message',
    icon: const Icon(Icons.more_vert, size: 18),
    onSelected: (choix) => choix == 'modifier' ? _modifier(context) : _supprimer(context),
    itemBuilder: (_) => const [
      PopupMenuItem(value: 'modifier', child: Text('Modifier')),
      PopupMenuItem(value: 'supprimer', child: Text('Supprimer')),
    ],
  );

  Future<void> _modifier(BuildContext context) async {
    final provider = context.read<ComplaintProvider>();
    final controle = TextEditingController(text: message.text);
    final texte = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Modifier le message'),
        content: TextField(controller: controle, maxLines: 6, minLines: 2, maxLength: 4000, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, controle.text.trim()), child: const Text('Enregistrer')),
        ],
      ),
    );
    controle.dispose();
    if (texte == null || texte.isEmpty || texte == message.text) return;
    await provider.updateResponse(message.id, texte, authorId: message.authorId);
  }

  Future<void> _supprimer(BuildContext context) async {
    final provider = context.read<ComplaintProvider>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Supprimer ce message ?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Supprimer')),
        ],
      ),
    );
    if (ok == true) await provider.deleteResponse(message.id, authorId: message.authorId);
  }
}

String _date(DateTime date) {
  final d = date.toLocal();
  String deux(int v) => v.toString().padLeft(2, '0');
  return '${deux(d.day)}/${deux(d.month)} ${deux(d.hour)}:${deux(d.minute)}';
}
