import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/constants/maintenance_options.dart';
import '../../models/demande_maintenance.dart';
import '../../models/photo_analysis.dart';
import '../../providers/demande_provider.dart';
import '../../providers/user_provider.dart';
import '../../services/demande_service.dart';
import '../../services/gemini_service.dart';

const _bordure = Color(0xFFE4EAF2);

class ValidateursDemande {
  const ValidateursDemande._();

  static final _lettre = RegExp(r'\p{L}', unicode: true);
  static final _nom = RegExp(r"^[\p{L} '\-]+$", unicode: true);
  static final _telephone = RegExp(r'^\d{8}$');

  static String? choix(Object? valeur) =>
      valeur == null ? 'Veuillez choisir une option' : null;

  static String? _texte(
    String? valeur,
    String champ, {
    required int min,
    required int max,
  }) {
    final texte = valeur?.trim() ?? '';
    if (texte.isEmpty) return '$champ est obligatoire';
    if (texte.length < min) return '$champ doit contenir au moins $min caractères';
    if (texte.length > max) return '$champ ne doit pas dépasser $max caractères';
    if (!_lettre.hasMatch(texte)) return '$champ doit contenir des lettres';
    return null;
  }

  static String? titre(String? valeur) =>
      _texte(valeur, 'Le titre', min: 5, max: 100);

  static String? description(String? valeur) =>
      _texte(valeur, 'La description', min: 15, max: 500);

  static String? nom(String? valeur) {
    final texte = valeur?.trim() ?? '';
    if (texte.isEmpty) return 'Le nom est obligatoire';
    if (texte.length < 3) return 'Le nom doit contenir au moins 3 caractères';
    if (texte.length > 50) return 'Le nom ne doit pas dépasser 50 caractères';
    if (!_nom.hasMatch(texte)) return 'Le nom ne doit contenir que des lettres';
    return null;
  }

  /// Numéro local de 8 chiffres d'un téléphone de profil (+216 ou 00216 retirés),
  /// ou null s'il n'a pas cette forme.
  static String? telephoneDepuisProfil(String? valeur) {
    final chiffres = (valeur ?? '').replaceAll(RegExp(r'[^0-9]'), '');
    return RegExp(r'^(?:00216|216)?(\d{8})$').firstMatch(chiffres)?.group(1);
  }

  static String? telephone(String? valeur) {
    final texte = valeur?.trim() ?? '';
    if (texte.isEmpty) return 'Le téléphone est obligatoire';
    if (!_telephone.hasMatch(texte)) {
      return 'Le numéro doit contenir exactement 8 chiffres';
    }
    return null;
  }
}

/// Contrôleur, focus et clé d'un champ texte validé à la perte de focus.
class _ChampTexte {
  _ChampTexte(String texte) : controller = TextEditingController(text: texte) {
    focus.addListener(_surChangementFocus);
  }

  final TextEditingController controller;
  final FocusNode focus = FocusNode();
  final GlobalKey<FormFieldState<String>> cle = GlobalKey();

  void _surChangementFocus() {
    if (!focus.hasFocus) cle.currentState?.validate();
  }

  /// Une fois l'erreur affichée, le champ est revalidé à chaque frappe.
  void surFrappe(String _) {
    if (cle.currentState?.hasError ?? false) cle.currentState?.validate();
  }

  void liberer() {
    focus.removeListener(_surChangementFocus);
    focus.dispose();
    controller.dispose();
  }
}

class DemandeFormScreen extends StatefulWidget {
  const DemandeFormScreen({super.key, this.demande});

  final DemandeMaintenance? demande;

  @override
  State<DemandeFormScreen> createState() => _DemandeFormScreenState();
}

class _DemandeFormScreenState extends State<DemandeFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _selecteur = ImagePicker();
  final _geminiService = GeminiService();
  final _cleLogement = GlobalKey<FormFieldState<String>>();
  final _cleCategorie = GlobalKey<FormFieldState<String>>();
  final _clePiece = GlobalKey<FormFieldState<String>>();
  final _cleUrgence = GlobalKey<FormFieldState<String>>();

  late final _ChampTexte _titre;
  late final _ChampTexte _description;
  late final _ChampTexte _nom;
  late final _ChampTexte _telephone;

  String? _logementId;
  String? _categorie;
  String? _piece;
  String? _urgence;
  String? _photoPath;
  bool _envoi = false;
  bool _analyzing = false;
  String? _analysisMessage;
  bool _analysisIsError = false;

  bool get _modification => widget.demande != null;

  @override
  void initState() {
    super.initState();
    final demande = widget.demande;
    final logements = context.read<DemandeProvider>().logements;
    _logementId =
        demande?.logementId ??
        (logements.length == 1 ? logements.first.annonceId : null);
    _titre = _ChampTexte(demande?.title ?? '');
    _description = _ChampTexte(demande?.description ?? '');
    final compte = context.read<UserProvider>().user;
    _nom = _ChampTexte(
      demande?.residentName ??
          (compte == null ? '' : '${compte.prenom} ${compte.nom}'.trim()),
    );
    _telephone = _ChampTexte(
      demande?.residentPhone ??
          ValidateursDemande.telephoneDepuisProfil(compte?.telephone) ??
          '',
    );
    _categorie = _optionConnue(
      MaintenanceOptions.categories,
      demande?.category,
    );
    _piece = _optionConnue(MaintenanceOptions.rooms, demande?.room);
    _urgence = _optionConnue(MaintenanceOptions.urgencies, demande?.urgency);
    final photo = demande?.photoPath;
    _photoPath = photo != null && File(photo).existsSync() ? photo : null;
  }

  String? _optionConnue(List<OptionItem> options, String? valeur) =>
      options.any((option) => option.value == valeur) ? valeur : null;

  @override
  void dispose() {
    _titre.liberer();
    _description.liberer();
    _nom.liberer();
    _telephone.liberer();
    _geminiService.fermer();
    super.dispose();
  }

  Future<void> _choisirPhoto() async {
    final messager = ScaffoldMessenger.of(context);
    try {
      final image = await _selecteur.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        imageQuality: 85,
      );
      if (image == null || !mounted) return;
      setState(() {
        _photoPath = image.path;
        _analysisMessage = null;
      });
      await _analyserPhoto();
    } on PlatformException {
      messager.showSnackBar(
        const SnackBar(content: Text("Impossible d'ouvrir la galerie")),
      );
    }
  }

  void _retirerPhoto() {
    setState(() {
      _photoPath = null;
      _analysisMessage = null;
    });
  }

  Future<void> _analyserPhoto() async {
    final chemin = _photoPath;
    if (chemin == null || _analyzing) return;
    setState(() {
      _analyzing = true;
      _analysisMessage = null;
      _analysisIsError = false;
    });
    try {
      final analyse = await _geminiService.analyserPhoto(File(chemin));
      if (mounted && _photoPath == chemin) _appliquerAnalyse(analyse);
    } on GeminiException catch (erreur) {
      if (mounted && _photoPath == chemin) {
        setState(() {
          _analysisMessage = erreur.message;
          _analysisIsError = true;
        });
      }
    } finally {
      if (mounted) setState(() => _analyzing = false);
    }
  }

  /// Ne remplit que les champs encore vides : la saisie de l'utilisateur prime.
  void _appliquerAnalyse(PhotoAnalysis analyse) {
    if (!analyse.isMaintenanceIssue) {
      setState(() {
        _analysisMessage =
            'Aucun problème de logement détecté sur cette photo. '
            'Remplis le formulaire à la main ou choisis une autre photo.';
        _analysisIsError = false;
      });
      return;
    }
    final categorie = _categorie == null
        ? _optionConnue(MaintenanceOptions.categories, analyse.category)
        : null;
    final piece = _piece == null
        ? _optionConnue(MaintenanceOptions.rooms, analyse.room)
        : null;
    final urgence = _urgence == null
        ? _optionConnue(MaintenanceOptions.urgencies, analyse.urgency)
        : null;
    setState(() {
      if (categorie != null) _categorie = categorie;
      if (piece != null) _piece = piece;
      if (urgence != null) _urgence = urgence;
      _analysisMessage =
          "Suggestions de l'IA appliquées. Vérifie et corrige avant d'envoyer.";
      _analysisIsError = false;
    });
    if (categorie != null) _cleCategorie.currentState?.didChange(categorie);
    if (piece != null) _clePiece.currentState?.didChange(piece);
    if (urgence != null) _cleUrgence.currentState?.didChange(urgence);
    _remplirSiVide(_titre, analyse.title);
    _remplirSiVide(_description, analyse.description);
  }

  void _remplirSiVide(_ChampTexte champ, String? valeur) {
    if (valeur != null && champ.controller.text.trim().isEmpty) {
      champ.controller.text = valeur;
    }
    champ.surFrappe('');
  }

  Future<void> _enregistrer() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _envoi = true);
    final provider = context.read<DemandeProvider>();
    final messager = ScaffoldMessenger.of(context);
    final navigateur = Navigator.of(context);
    final origine = widget.demande;
    final demande = DemandeMaintenance(
      id: origine?.id ?? '',
      userId: origine?.userId ?? provider.utilisateurId ?? '',
      logementId: _logementId,
      category: _categorie!,
      room: _piece!,
      urgency: _urgence!,
      title: _titre.controller.text.trim(),
      description: _description.controller.text.trim(),
      residentName: _nom.controller.text.trim(),
      residentPhone: _telephone.controller.text.trim(),
      photoPath: _photoPath,
      createdAt: origine?.createdAt ?? DateTime.now(),
    );
    try {
      if (origine == null) {
        await provider.ajouter(demande);
      } else {
        await provider.modifier(demande);
      }
      messager.showSnackBar(
        SnackBar(
          content: Text(
            origine == null ? 'Demande enregistrée' : 'Demande modifiée',
          ),
        ),
      );
      navigateur.pop();
    } on DemandeAccesRefuse catch (refus) {
      messager.showSnackBar(SnackBar(content: Text(refus.message)));
      if (mounted) setState(() => _envoi = false);
    } catch (error) {
      debugPrint('Enregistrement de la demande impossible : $error');
      messager.showSnackBar(
        const SnackBar(content: Text("Erreur lors de l'enregistrement")),
      );
      if (mounted) setState(() => _envoi = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final libelleBouton = _envoi
        ? 'Envoi...'
        : _modification
        ? 'Enregistrer les modifications'
        : 'Envoyer la demande';
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Retour à la liste',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          _modification
              ? 'Modifier la demande'
              : "Nouvelle demande d'intervention",
        ),
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => FocusScope.of(context).unfocus(),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 16,
                    children: [
                      _zonePhoto(),
                      _liste(
                        cle: _cleLogement,
                        label: 'Logement concerné',
                        options: _optionsLogement(),
                        valeur: _logementId,
                        onChanged: (v) => setState(() => _logementId = v),
                      ),
                      if (_nomProprietaire() case final nom?)
                        InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Propriétaire',
                          ),
                          child: Text(nom),
                        ),
                      _liste(
                        cle: _cleCategorie,
                        label: 'Catégorie',
                        options: MaintenanceOptions.categories,
                        valeur: _categorie,
                        onChanged: (v) => setState(() => _categorie = v),
                      ),
                      _liste(
                        cle: _clePiece,
                        label: 'Pièce concernée',
                        options: MaintenanceOptions.rooms,
                        valeur: _piece,
                        onChanged: (v) => setState(() => _piece = v),
                      ),
                      _liste(
                        cle: _cleUrgence,
                        label: 'Urgence',
                        options: MaintenanceOptions.urgencies,
                        valeur: _urgence,
                        onChanged: (v) => setState(() => _urgence = v),
                      ),
                      _champ(
                        _titre,
                        label: 'Titre',
                        validator: ValidateursDemande.titre,
                      ),
                      _champ(
                        _description,
                        label: 'Description',
                        validator: ValidateursDemande.description,
                        lignes: 4,
                      ),
                      _champ(
                        _nom,
                        label: 'Nom du résident',
                        validator: ValidateursDemande.nom,
                      ),
                      _champ(
                        _telephone,
                        label: 'Téléphone',
                        validator: ValidateursDemande.telephone,
                        clavier: TextInputType.phone,
                        formats: [FilteringTextInputFormatter.digitsOnly],
                        longueurMax: 8,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _envoi ? null : _enregistrer,
                    child: Text(libelleBouton),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Propriétaire du logement sélectionné, en lecture seule.
  String? _nomProprietaire() {
    for (final logement in context.watch<DemandeProvider>().logements) {
      if (logement.annonceId == _logementId) return logement.proprietaireNom;
    }
    final origine = widget.demande;
    return origine?.logementId == _logementId ? origine?.proprietaireNom : null;
  }

  /// Logements loués, plus celui de la demande si sa location est terminée.
  List<OptionItem> _optionsLogement() {
    final options = [
      for (final logement in context.watch<DemandeProvider>().logements)
        OptionItem(logement.annonceId, logement.titre),
    ];
    final origine = widget.demande;
    final id = origine?.logementId;
    if (id != null && options.every((option) => option.value != id)) {
      options.add(OptionItem(id, origine?.logementTitre ?? 'Logement'));
    }
    return options;
  }

  Widget _zonePhoto() {
    final photo = _photoPath;
    if (photo != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.file(File(photo), height: 200, fit: BoxFit.cover),
          ),
          if (_analyzing)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 12),
                  Text('Analyse de la photo en cours...'),
                ],
              ),
            ),
          if (_analysisMessage != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _analysisMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _analysisIsError
                      ? Theme.of(context).colorScheme.error
                      : const Color(0xFF14263F),
                ),
              ),
            ),
          Wrap(
            alignment: WrapAlignment.center,
            children: [
              TextButton.icon(
                onPressed: _analyzing ? null : _analyserPhoto,
                icon: const Icon(Icons.auto_awesome),
                label: const Text('Analyser à nouveau'),
              ),
              TextButton.icon(
                onPressed: _analyzing ? null : _retirerPhoto,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Retirer'),
              ),
            ],
          ),
        ],
      );
    }
    return Material(
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: _bordure),
      ),
      child: InkWell(
        onTap: _choisirPhoto,
        child: const SizedBox(
          height: 140,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_a_photo_outlined, size: 36),
              SizedBox(height: 8),
              Text(
                "Ajouter une photo (analyse automatique par l'IA)",
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _liste({
    required GlobalKey<FormFieldState<String>> cle,
    required String label,
    required List<OptionItem> options,
    required String? valeur,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      key: cle,
      initialValue: valeur,
      isExpanded: true,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      decoration: InputDecoration(labelText: label),
      validator: ValidateursDemande.choix,
      items: [
        for (final option in options)
          DropdownMenuItem(value: option.value, child: Text(option.label)),
      ],
      onChanged: onChanged,
    );
  }

  Widget _champ(
    _ChampTexte champ, {
    required String label,
    required FormFieldValidator<String> validator,
    int lignes = 1,
    TextInputType? clavier,
    List<TextInputFormatter>? formats,
    int? longueurMax,
  }) {
    return TextFormField(
      key: champ.cle,
      controller: champ.controller,
      focusNode: champ.focus,
      maxLines: lignes,
      keyboardType: clavier,
      inputFormatters: formats,
      maxLength: longueurMax,
      onChanged: champ.surFrappe,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        alignLabelWithHint: lignes > 1,
        counterText: longueurMax == null ? null : '',
      ),
    );
  }
}
