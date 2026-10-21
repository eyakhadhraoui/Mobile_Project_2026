import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../../core/utils/validators.dart';
import '../../models/complaint_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/complaint_provider.dart';
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
  }

  @override
  void dispose() {
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

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
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
      priority: _priority,
      createdAt: current?.createdAt ?? now,
      history: current?.history ?? [ComplaintHistoryEntry(status: ComplaintStatus.ouverte, date: now)],
    );
    try {
      final provider = context.read<ComplaintProvider>();
      if (current == null) {
        await provider.create(complaint);
        if (mounted) {
          Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
            builder: (_) => ComplaintSuccessScreen(complaint: complaint),
          ));
        }
      } else {
        await provider.update(complaint);
        if (mounted) Navigator.of(context).pop();
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
              ),
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
                return Expanded(child: Padding(padding: const EdgeInsets.only(right: 8), child: OutlinedButton(
                  onPressed: () => setState(() => _priority = priority),
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), backgroundColor: selected ? color.withValues(alpha: .10) : Colors.white, foregroundColor: selected ? color : const Color(0xFF172B45), side: BorderSide(color: selected ? color : const Color(0xFFDCE7F1)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                  child: Text(_priorityName(priority), style: const TextStyle(fontSize: 12)),
                )));
              }).toList()),
              const SizedBox(height: 18),
              SizedBox(height: 56, child: FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2)) : Text(editing ? 'Enregistrer les modifications' : 'Envoyer la réclamation'),
              )),
            ],
          ),
        ),
      ),
    );
  }

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
