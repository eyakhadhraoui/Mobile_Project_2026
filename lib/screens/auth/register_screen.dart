import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../../core/utils/validators.dart';
import '../../models/trajet.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/mot_de_passe_provider.dart';
import '../../services/geocodage_service.dart';
import '../../services/welcome_email_service.dart';
import '../../widgets/indicateur_mot_de_passe.dart';
import '../covoiturage/choisir_position_screen.dart';
import 'email_verification_dialog.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmationController = TextEditingController();
  UserRole _role = UserRole.locataire;
  bool _acceptedTerms = false;
  bool _obscurePassword = true;
  bool _obscureConfirmation = true;

  /// Force du mot de passe et vérification des fuites (Pwned Passwords).
  final _verification = MotDePasseProvider();
  bool _verificationEnCours = false;

  /// Photo choisie : copiée dans le dossier de l'application une fois le compte vérifié.
  String? _photoChoisie;

  /// Faculté de l'étudiant, placée sur la carte.
  final _nomFac = TextEditingController();
  final _geocodage = GeocodageService();
  LatLng? _positionFac;
  bool _rechercheFac = false;

  @override
  void dispose() {
    _geocodage.fermer();
    _nomFac.dispose();
    _verification.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmationController.dispose();
    super.dispose();
  }

  void _message(String texte) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(texte)));

  Future<void> _choisirPhoto() async {
    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 82,
        maxWidth: 1024,
      );
      if (image != null && mounted) {
        setState(() => _photoChoisie = image.path);
      }
    } on PlatformException {
      if (mounted) _message('Impossible d’ouvrir la galerie.');
    }
  }

  /// La photo est facultative : un échec de copie ne doit pas bloquer le compte.
  Future<String?> _copierPhoto(String userId) async {
    final source = _photoChoisie;
    if (source == null) return null;
    try {
      final documents = await getApplicationDocumentsDirectory();
      final dossier = Directory(p.join(documents.path, 'profile_photos'));
      await dossier.create(recursive: true);
      final copie = await File(source).copy(
        p.join(dossier.path, '${userId}_${p.basename(source)}'),
      );
      return copie.path;
    } on FileSystemException {
      return null;
    }
  }

  Future<void> _choisirFac() async {
    final point = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute(
        builder: (_) => ChoisirPositionScreen(
          titre: 'Localisation de ma fac',
          zone: 'tunis',
          initiale: _positionFac,
          choixVille: true,
        ),
      ),
    );
    if (point == null || !mounted) return;
    setState(() {
      _positionFac = point;
      _rechercheFac = true;
    });
    String? lieu;
    try {
      lieu = await _geocodage.lieuDe(point.latitude, point.longitude);
    } on GeocodageIndisponibleException {
      lieu = null;
    }
    if (!mounted) return;
    setState(() {
      _rechercheFac = false;
      if (lieu != null) _nomFac.text = lieu;
    });
  }

  /// La faculté n'est conservée que pour un compte étudiant.
  Map<String, dynamic> _preferencesInitiales() {
    final position = _positionFac;
    if (_role != UserRole.locataire || position == null) return const {};
    return {
      Universite.clePreference: Universite(
        nom: _nomFac.text.trim(),
        lat: position.latitude,
        lon: position.longitude,
      ).toMap(),
    };
  }

  Future<void> _register() async {
    if (_rechercheFac || !_formKey.currentState!.validate()) return;
    if (!_acceptedTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Veuillez accepter les conditions.')),
      );
      return;
    }
    // Vérification des fuites au moment de la validation (en plus de l'anti-rebond).
    setState(() => _verificationEnCours = true);
    final motDePasseAccepte = await autoriserMotDePasse(context, _verification, _passwordController.text);
    if (!mounted) return;
    setState(() => _verificationEnCours = false);
    if (!motDePasseAccepte) return;

    final parts = _nameController.text.trim().split(RegExp(r'\s+'));
    final firstName = parts.first;
    final lastName = parts.length > 1 ? parts.skip(1).join(' ') : '';
    final user = UserModel(
      id: '${DateTime.now().microsecondsSinceEpoch}_${Random.secure().nextInt(1 << 32)}',
      nom: lastName,
      prenom: firstName,
      email: _emailController.text.trim(),
      telephone: _phoneController.text.trim(),
      rolePrincipal: _role,
      preferences: _preferencesInitiales(),
    );

    try {
      final auth = context.read<AuthProvider>();
      final existingUser = await auth.getUserByEmail(user.email);
      if (existingUser != null && existingUser.emailVerified) {
        throw Exception('Cette adresse e-mail est déjà utilisée.');
      }
      const mailService = WelcomeEmailService();
      final targetEmail = existingUser?.email ?? user.email;
      final targetFirstName = existingUser?.prenom ?? user.prenom;
      final emailStatus = await mailService.sendWelcome(
        email: targetEmail,
        firstName: targetFirstName,
      );
      if (!mounted) return;
      if (emailStatus != WelcomeEmailStatus.sent) {
        final reason = EmailVerificationDialog.describeSendFailure(emailStatus);
        final message = '$reason Aucun compte n’a été créé.';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
        return;
      }
      final verificationToken = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (_) => EmailVerificationDialog(
          email: targetEmail,
          firstName: targetFirstName,
        ),
      );
      if (!mounted) return;
      if (verificationToken == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Inscription annulée : l’adresse e-mail doit être vérifiée.')),
        );
        return;
      }
      if (existingUser != null) {
        await auth.markEmailVerified(existingUser.id);
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Adresse e-mail vérifiée'),
            content: const Text('Votre adresse e-mail est vérifiée et votre compte est activé.'),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Continuer'),
              ),
            ],
          ),
        );
        if (mounted) Navigator.of(context).pop();
        return;
      }
      final photo = await _copierPhoto(user.id);
      try {
        await auth.register(
          user: user.copyWith(photo: photo),
          password: _passwordController.text,
          verificationToken: verificationToken,
        );
      } catch (_) {
        if (photo != null) await File(photo).delete();
        rethrow;
      }
      if (!mounted) return;
      if (_photoChoisie != null && photo == null) {
        _message('Photo non enregistrée : ajoutez-la depuis votre profil.');
      }
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Adresse e-mail vérifiée'),
          content: const Text('Votre adresse e-mail est vérifiée et votre compte est activé.'),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Continuer'),
            ),
          ],
        ),
      );
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      final message = error.toString().replaceFirst('Exception: ', '');
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back),
        ),
        title: const _BrandTitle(),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            theme.colorScheme.primaryContainer,
                            theme.colorScheme.primaryContainer.withValues(
                              alpha: .35,
                            ),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Column(
                        children: [
                          _AvatarInscription(
                            chemin: _photoChoisie,
                            onTap: _choisirPhoto,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Rejoignez-nous !',
                            style: theme.textTheme.titleLarge,
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Tous vos services du quotidien, au même endroit.',
                            textAlign: TextAlign.center,
                          ),
                          TextButton(
                            onPressed: _photoChoisie == null
                                ? _choisirPhoto
                                : () => setState(() => _photoChoisie = null),
                            child: Text(
                              _photoChoisie == null
                                  ? 'Ajouter une photo (facultatif)'
                                  : 'Retirer la photo',
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    _label('Nom complet'),
                    TextFormField(
                      controller: _nameController,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.person_outline),
                        hintText: 'Votre nom et prénom',
                      ),
                      validator: (value) =>
                          Validators.required(value, label: 'Le nom'),
                    ),
                    const SizedBox(height: 16),
                    _label('Adresse e-mail'),
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.mail_outline),
                        hintText: 'exemple@email.com',
                      ),
                      validator: Validators.email,
                    ),
                    const SizedBox(height: 16),
                    _label('Numéro de téléphone'),
                    TextFormField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.phone_outlined),
                        hintText: '+216 00 000 000',
                      ),
                      validator: (value) => Validators.required(
                        value,
                        label: 'Le numéro de téléphone',
                      ),
                    ),
                    const SizedBox(height: 16),
                    _label('Créer un mot de passe'),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.lock_outline),
                        hintText: '8 caractères minimum',
                        suffixIcon: IconButton(
                          onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                      onChanged: _verification.surSaisie,
                      validator: Validators.nouveauMotDePasse,
                    ),
                    ChangeNotifierProvider.value(
                      value: _verification,
                      child: const IndicateurMotDePasse(),
                    ),
                    const SizedBox(height: 16),
                    _label('Confirmer le mot de passe'),
                    TextFormField(
                      controller: _confirmationController,
                      obscureText: _obscureConfirmation,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _register(),
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.lock_outline),
                        hintText: 'Répétez votre mot de passe',
                        suffixIcon: IconButton(
                          onPressed: () => setState(
                            () => _obscureConfirmation = !_obscureConfirmation,
                          ),
                          icon: Icon(
                            _obscureConfirmation
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                      validator: (value) => value != _passwordController.text
                          ? 'Les mots de passe ne correspondent pas.'
                          : null,
                    ),
                    const SizedBox(height: 20),
                    _label('Je suis'),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _RoleChoice(
                          selected: _role == UserRole.locataire,
                          icon: Icons.person_outline,
                          label: 'Étudiant / locataire',
                          onTap: () =>
                              setState(() => _role = UserRole.locataire),
                        ),
                        _RoleChoice(
                          selected: _role == UserRole.proprietaire,
                          icon: Icons.apartment_outlined,
                          label: 'Propriétaire',
                          onTap: () =>
                              setState(() => _role = UserRole.proprietaire),
                        ),
                        _RoleChoice(
                          selected: _role == UserRole.prestataire,
                          icon: Icons.handyman_outlined,
                          label: 'Prestataire',
                          onTap: () =>
                              setState(() => _role = UserRole.prestataire),
                        ),
                      ],
                    ),
                    if (_role == UserRole.locataire) ...[
                      const SizedBox(height: 16),
                      _blocFac(theme),
                    ],
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _acceptedTerms,
                      onChanged: (value) =>
                          setState(() => _acceptedTerms = value ?? false),
                      title: const Text(
                        'J’accepte les conditions d’utilisation.',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Consumer<AuthProvider>(
                      builder: (context, auth, _) => FilledButton(
                        onPressed: auth.isLoading || _verificationEnCours || _rechercheFac ? null : _register,
                        child: auth.isLoading || _verificationEnCours
                            ? const SizedBox.square(
                                dimension: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Créer mon compte'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(String label) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(label, style: Theme.of(context).textTheme.labelLarge),
  );

  Widget _blocFac(ThemeData theme) {
    final placee = _positionFac != null;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.school_outlined, color: theme.colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Ma fac (facultatif)',
                  style: theme.textTheme.titleSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Elle sert à calculer le temps de trajet vers les logements.',
          ),
          const SizedBox(height: 10),
          if (placee) ...[
            TextFormField(
              controller: _nomFac,
              maxLength: 120,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Nom de la fac',
                prefixIcon: Icon(Icons.edit_outlined),
                counterText: '',
              ),
              validator: (value) =>
                  Validators.required(value, label: 'Le nom de la fac'),
            ),
            const SizedBox(height: 10),
          ],
          OutlinedButton.icon(
            onPressed: _rechercheFac ? null : _choisirFac,
            icon: _rechercheFac
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.map_outlined),
            label: Text(
              _rechercheFac
                  ? 'Recherche du lieu…'
                  : placee
                  ? 'Modifier sur la carte'
                  : 'Choisir sur la carte',
            ),
          ),
          if (placee && !_rechercheFac)
            TextButton(
              onPressed: () => setState(() {
                _positionFac = null;
                _nomFac.clear();
              }),
              child: const Text('Retirer la fac'),
            ),
        ],
      ),
    );
  }
}

class _AvatarInscription extends StatelessWidget {
  const _AvatarInscription({required this.chemin, required this.onTap});

  final String? chemin;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final couleurs = Theme.of(context).colorScheme;
    final image = chemin;
    return Semantics(
      button: true,
      label: 'Choisir une photo de profil',
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            CircleAvatar(
              radius: 46,
              backgroundColor: couleurs.surface,
              foregroundImage: image == null ? null : FileImage(File(image)),
              child: Icon(
                Icons.person_outline,
                size: 46,
                color: couleurs.primary,
              ),
            ),
            Positioned(
              right: -2,
              bottom: -2,
              child: CircleAvatar(
                radius: 15,
                backgroundColor: couleurs.primary,
                child: Icon(
                  Icons.photo_camera_outlined,
                  size: 16,
                  color: couleurs.onPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoleChoice extends StatelessWidget {
  const _RoleChoice({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: .10) : null,
          border: Border.all(
            color: selected
                ? color
                : Theme.of(context).colorScheme.outlineVariant,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: selected ? color : null, size: 19),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                style: TextStyle(color: selected ? color : null),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BrandTitle extends StatelessWidget {
  const _BrandTitle();

  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(
      children: [
        const TextSpan(text: 'Student'),
        TextSpan(
          text: 'Hub',
          style: TextStyle(color: Theme.of(context).colorScheme.primary),
        ),
      ],
    ),
    style: Theme.of(context).textTheme.titleLarge
        ?.copyWith(fontWeight: FontWeight.w800),
  );
}
