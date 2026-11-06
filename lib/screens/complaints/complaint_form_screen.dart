import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../../core/utils/detecteur_danger.dart';
import '../../core/utils/validators.dart';
import '../../models/complaint_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/complaint_provider.dart';
import '../../services/tri_reclamation_service.dart';
import 'complaint_success_screen.dart';

class ComplaintFormScreen extends StatefulWidget {
  const ComplaintFormScreen({super.key, this.complaint});
  final ComplaintModel? complaint;

  @override
  State<ComplaintFormScreen> createState() => _ComplaintFormScreenState();
}

class _ComplaintFormScreenState extends State<ComplaintFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _locationController;
  late final TextEditingController _subjectController;
  late final TextEditingController _descriptionController;
  late ComplaintCategory _category;
  late ComplaintPriority _priority;
  late List<String> _photos;
  bool _saving = false;

  /// Tri automatique : dangers détectés localement (immédiat, hors ligne) et
  /// proposition de l'IA (sur demande, affichée avec un FutureBuilder).
  final _tri = TriReclamationService();
  List<DangerDetecte> _dangers = const [];
  bool _dangerIgnore = false;
  Future<SuggestionTri>? _analyse;
  bool _suggestionAppliquee = false;

  /// Un danger détecté impose la priorité urgente (sauf confirmation contraire).
  bool get _urgenceImposee => _dangers.isNotEmpty && !_dangerIgnore;

  @override
  void initState() {
    super.initState();
    final complaint = widget.complaint;
    _locationController = TextEditingController(text: complaint?.locationId ?? '');
    _subjectController = TextEditingController(text: complaint?.subject ?? '');
    _descriptionController = TextEditingController(text: complaint?.description ?? '');
    _category = complaint?.category ?? ComplaintCategory.fuiteEau;
    _priority = complaint?.priority ?? ComplaintPriority.moyenne;
    _photos = [...?complaint?.photos];
    _dangers = detecterDangers('${_subjectController.text}\n${_descriptionController.text}');
  }

  /// Détection des dangers à chaque frappe (mots-clés, sans réseau).
  void _majDangers() {
    final dangers = detecterDangers('${_subjectController.text}\n${_descriptionController.text}');
    final nouveauType = dangers.any((d) => !_dangers.any((ancien) => ancien.type == d.type));
    setState(() {
      _dangers = dangers;
      if (nouveauType) _dangerIgnore = false;
      if (_urgenceImposee) _priority = ComplaintPriority.urgente;
    });
  }

  void _analyser() => setState(() {
    _suggestionAppliquee = false;
    _analyse = _tri.analyser(titre: _subjectController.text, description: _descriptionController.text);
  });

  void _appliquer(SuggestionTri suggestion) => setState(() {
    if (suggestion.categorie != null) _category = suggestion.categorie!;
    _priority = _urgenceImposee ? ComplaintPriority.urgente : suggestion.priorite;
    if (_subjectController.text.trim().isEmpty && suggestion.resume.isNotEmpty) _subjectController.text = suggestion.resume;
    _suggestionAppliquee = true;
  });

  Future<void> _ignorerDanger() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Ce n’est pas une urgence ?'),
        content: const Text('Confirmez qu’il n’y a aucun risque pour les personnes. Vous pourrez alors choisir une autre priorité.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Garder urgente')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Aucun danger')),
        ],
      ),
    );
    if (ok == true && mounted) setState(() => _dangerIgnore = true);
  }

  @override
  void dispose() {
    _tri.fermer();
    _locationController.dispose();
    _subjectController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickPhotos() async {
    final remaining = 5 - _photos.length;
    if (remaining <= 0) return;
    final selected = await ImagePicker().pickMultiImage(imageQuality: 82);
    if (selected.isEmpty || !mounted) return;
    final directory = await getApplicationDocumentsDirectory();
    final photoDirectory = Directory(p.join(directory.path, 'complaint_photos'));
    await photoDirectory.create(recursive: true);
    final copied = <String>[];
    for (final photo in selected.take(remaining)) {
      final filename = '${DateTime.now().microsecondsSinceEpoch}_${p.basename(photo.path)}';
      final saved = await File(photo.path).copy(p.join(photoDirectory.path, filename));
      copied.add(saved.path);
    }
    if (mounted) setState(() => _photos.addAll(copied));
  }

  Future<void> _save({bool asDraft = false}) async {
    if (!asDraft && !_formKey.currentState!.validate()) return;
    final userId = context.read<AuthProvider>().currentUserId;
    if (userId == null) return;
    setState(() => _saving = true);
    final current = widget.complaint;
    final now = DateTime.now();
    final description = _descriptionController.text.trim();
    final firstLine = description.split('\n').first;
    final subject = _subjectController.text.trim().isNotEmpty
        ? _subjectController.text.trim()
        : firstLine.substring(0, firstLine.length > 52 ? 52 : firstLine.length);
    final complaint = ComplaintModel(
      id: current?.id ?? '${now.microsecondsSinceEpoch}',
      userId: userId,
      locationId: _locationController.text.trim(),
      subject: subject,
      category: _category,
      description: description,
      photos: List.unmodifiable(_photos),
      status: current?.status ?? ComplaintStatus.ouverte,
      // Urgence jamais oubliée : un danger détecté force la priorité.
      priority: _urgenceImposee ? ComplaintPriority.urgente : _priority,
      createdAt: current?.createdAt ?? now,
      history: current?.history ?? [ComplaintHistoryEntry(status: ComplaintStatus.ouverte, date: now)],
      isDraft: asDraft,
      syncStatus: ComplaintSyncStatus.pending,
    );
    try {
      final provider = context.read<ComplaintProvider>();
      if (current == null) {
        await provider.create(complaint);
        if (!asDraft) await provider.syncNow();
        final savedComplaint = await provider.complaintById(complaint.id) ?? complaint;
        if (mounted) {
          if (asDraft) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Brouillon enregistré sur cet appareil.')));
            Navigator.of(context).pop();
          } else {
            Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
              builder: (_) => ComplaintSuccessScreen(complaint: savedComplaint),
            ));
          }
        }
      } else {
        await provider.update(complaint);
        if (!asDraft) await provider.syncNow();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(asDraft ? 'Brouillon enregistré sur cet appareil.' : 'Réclamation enregistrée. La synchronisation se fera dès que possible.')));
          Navigator.of(context).pop();
        }
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.complaint != null;
    return Scaffold(
      appBar: AppBar(title: Text(editing ? 'Modifier la réclamation' : 'Signaler un problème')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
            children: [
              _label('Logement concerné'),
              TextFormField(
                controller: _locationController,
                decoration: const InputDecoration(
                  hintText: 'Appartement ou référence du logement',
                  prefixIcon: Icon(Icons.apartment_outlined),
                  suffixIcon: Icon(Icons.chevron_right),
                ),
                validator: (value) => Validators.required(value, label: 'Le logement'),
              ),
              const SizedBox(height: 22),
              _label('Type de problème'),
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.12,
                children: _categoryOptions.map((item) {
                  final selected = _category == item.$1;
                  return InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => setState(() => _category = item.$1),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      decoration: BoxDecoration(
                        color: selected ? const Color(0xFFEAF5FF) : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: selected ? Theme.of(context).colorScheme.primary : const Color(0xFFDCE7F1), width: selected ? 1.4 : 1),
                      ),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(item.$2, size: 25, color: selected ? Theme.of(context).colorScheme.primary : const Color(0xFF172B45)),
                        const SizedBox(height: 8),
                        Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: Text(item.$3, textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: selected ? Theme.of(context).colorScheme.primary : const Color(0xFF172B45)))),
                      ]),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 18),
              _label('Titre de la demande'),
              TextFormField(
                controller: _subjectController,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => _majDangers(),
                decoration: const InputDecoration(hintText: 'Ex. : Fuite d’eau dans la cuisine'),
              ),
              const SizedBox(height: 18),
              _label('Décrivez le problème'),
              TextFormField(
                controller: _descriptionController,
                minLines: 4,
                maxLines: 6,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(hintText: 'Ajoutez les détails utiles…', alignLabelWithHint: true),
                validator: (value) => Validators.required(value, label: 'La description'),
                onChanged: (_) => _majDangers(),
              ),
              if (_urgenceImposee) ...[const SizedBox(height: 12), _AlerteDanger(dangers: _dangers, onIgnorer: _ignorerDanger)],
              const SizedBox(height: 12),
              _sectionTri(),
              const SizedBox(height: 20),
              _label('Ajouter des photos (facultatif)'),
              InkWell(
                onTap: _pickPhotos,
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFB8D9F7), style: BorderStyle.solid)),
                  child: Column(children: [
                    Icon(Icons.photo_camera_outlined, color: Theme.of(context).colorScheme.primary, size: 27),
                    const SizedBox(height: 6),
                    Text(_photos.isEmpty ? 'Ajouter une photo' : 'Ajouter des photos', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 3),
                    Text('${_photos.length}/5 photos · JPG ou PNG', style: Theme.of(context).textTheme.bodySmall),
                  ]),
                ),
              ),
              if (_photos.isNotEmpty) ...[
                const SizedBox(height: 12),
                SizedBox(height: 82, child: ListView.separated(scrollDirection: Axis.horizontal, itemCount: _photos.length, separatorBuilder: (_, _) => const SizedBox(width: 9), itemBuilder: (context, index) => Stack(children: [
                  ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.file(File(_photos[index]), width: 82, height: 82, fit: BoxFit.cover)),
                  Positioned(right: 0, top: 0, child: IconButton.filledTonal(visualDensity: VisualDensity.compact, onPressed: () => setState(() => _photos.removeAt(index)), icon: const Icon(Icons.close, size: 16))),
                ]))),
              ],
              const SizedBox(height: 20),
              _label('Niveau de priorité'),
              Row(children: ComplaintPriority.values.map((priority) {
                final selected = _priority == priority;
                final color = priority == ComplaintPriority.urgente ? const Color(0xFFE46B45) : priority == ComplaintPriority.moyenne ? const Color(0xFFEBA23B) : const Color(0xFF62B67E);
                final bloquee = _urgenceImposee && priority != ComplaintPriority.urgente;
                return Expanded(child: Padding(padding: const EdgeInsets.only(right: 8), child: OutlinedButton(
                  onPressed: bloquee ? null : () => setState(() => _priority = priority),
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), backgroundColor: selected ? color.withValues(alpha: .10) : Colors.white, foregroundColor: selected ? color : const Color(0xFF172B45), side: BorderSide(color: selected ? color : const Color(0xFFDCE7F1)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                  child: Text(_priorityName(priority), style: const TextStyle(fontSize: 12)),
                )));
              }).toList()),
              const SizedBox(height: 18),
              if (!editing || widget.complaint!.isDraft) ...[
                SizedBox(height: 50, child: OutlinedButton.icon(
                  onPressed: _saving ? null : () => _save(asDraft: true),
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Enregistrer en brouillon'),
                )),
                const SizedBox(height: 9),
              ],
              SizedBox(height: 56, child: FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2)) : Text(editing ? (widget.complaint!.isDraft ? 'Envoyer la réclamation' : 'Enregistrer les modifications') : 'Envoyer la réclamation'),
              )),
            ],
          ),
        ),
      ),
    );
  }

  /// Bouton « Analyser avec l'IA » et proposition (FutureBuilder).
  Widget _sectionTri() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ValueListenableBuilder(
        valueListenable: _descriptionController,
        builder: (context, valeur, _) => OutlinedButton.icon(
          onPressed: valeur.text.trim().length < 10 ? null : _analyser,
          icon: const Icon(Icons.auto_awesome_outlined),
          label: const Text('Analyser avec l’IA (catégorie, priorité, titre)'),
        ),
      ),
      if (_analyse != null)
        FutureBuilder<SuggestionTri>(
          future: _analyse,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Row(children: [
                  SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 10),
                  Text('Analyse en cours…', style: TextStyle(fontSize: 12)),
                ]),
              );
            }
            if (snapshot.hasError) {
              final message = snapshot.error is TriReclamationException ? (snapshot.error! as TriReclamationException).message : 'Erreur inattendue.';
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Analyse indisponible : $message Choisissez la catégorie et la priorité vous-même.', style: const TextStyle(fontSize: 12, color: Color(0xFF8A5A00))),
              );
            }
            return _CarteSuggestion(suggestion: snapshot.data!, appliquee: _suggestionAppliquee, onAppliquer: () => _appliquer(snapshot.data!));
          },
        ),
    ],
  );

  Widget _label(String label) => Padding(padding: const EdgeInsets.only(bottom: 9), child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF172B45))));
}

const _categoryOptions = <(ComplaintCategory, IconData, String)>[
  (ComplaintCategory.fuiteEau, Icons.water_drop_outlined, 'Fuite d’eau'),
  (ComplaintCategory.electricite, Icons.bolt_outlined, 'Électricité'),
  (ComplaintCategory.chauffage, Icons.ac_unit, 'Chauffage'),
  (ComplaintCategory.equipement, Icons.handyman_outlined, 'Équipement endommagé'),
  (ComplaintCategory.proprietaire, Icons.person_outline, 'Problème propriétaire'),
  (ComplaintCategory.autre, Icons.warning_amber_outlined, 'Autre'),
];

String _priorityName(ComplaintPriority priority) => switch (priority) {
  ComplaintPriority.faible => 'Faible',
  ComplaintPriority.moyenne => 'Moyenne',
  ComplaintPriority.urgente => 'Urgente',
};

/// Proposition de l'IA, appliquée seulement si l'étudiant le décide.
class _CarteSuggestion extends StatelessWidget {
  const _CarteSuggestion({required this.suggestion, required this.appliquee, required this.onAppliquer});
  final SuggestionTri suggestion;
  final bool appliquee;
  final VoidCallback onAppliquer;

  @override
  Widget build(BuildContext context) {
    final categorie = suggestion.categorie;
    final libelle = categorie == null ? null : _categoryOptions.where((o) => o.$1 == categorie).firstOrNull?.$3;
    return Card(
      margin: const EdgeInsets.only(top: 10),
      color: const Color(0xFFF1F7FD),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.auto_awesome, size: 18, color: Color(0xFF326D98)),
            SizedBox(width: 6),
            Text('Proposition de l’IA', style: TextStyle(fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 8),
          if (libelle != null) Text('Catégorie : $libelle', style: const TextStyle(fontSize: 13)),
          Text('Priorité : ${_priorityName(suggestion.priorite)}${suggestion.danger ? ' (danger signalé)' : ''}', style: const TextStyle(fontSize: 13)),
          if (suggestion.resume.isNotEmpty) Text('Titre : ${suggestion.resume}', style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: appliquee
                ? const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.check_circle, size: 16, color: Color(0xFF16804A)),
                    SizedBox(width: 4),
                    Text('Proposition appliquée', style: TextStyle(fontSize: 12, color: Color(0xFF16804A))),
                  ])
                : FilledButton.tonal(onPressed: onAppliquer, child: const Text('Appliquer')),
          ),
        ]),
      ),
    );
  }
}

/// Alerte de sécurité : dangers détectés et consignes immédiates.
class _AlerteDanger extends StatelessWidget {
  const _AlerteDanger({required this.dangers, required this.onIgnorer});
  final List<DangerDetecte> dangers;
  final VoidCallback onIgnorer;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: const Color(0xFFFDECEA), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE7A49B))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Icon(Icons.warning_amber_rounded, color: Color(0xFFC53030)),
        const SizedBox(width: 8),
        Expanded(child: Text('${dangers.map((d) => d.libelle).join(' · ')} : priorité urgente', style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFFC53030)))),
      ]),
      const SizedBox(height: 8),
      for (final consigne in {for (final d in dangers) ...d.consignes})
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('•  ', style: TextStyle(color: Color(0xFF7A1F1F))),
            Expanded(child: Text(consigne, style: const TextStyle(fontSize: 12, color: Color(0xFF7A1F1F)))),
          ]),
        ),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton(onPressed: onIgnorer, child: const Text('Ce n’est pas une urgence')),
      ),
    ]),
  );
}
