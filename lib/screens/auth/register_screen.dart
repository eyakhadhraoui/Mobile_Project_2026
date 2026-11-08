import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/utils/validators.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/mot_de_passe_provider.dart';
import '../../services/welcome_email_service.dart';
import '../../widgets/indicateur_mot_de_passe.dart';
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

  @override
  void dispose() {
    _verification.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmationController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
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
      preferences: const {},
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
      await auth.register(
        user: user,
        password: _passwordController.text,
        verificationToken: verificationToken,
      );
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
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer.withValues(
                          alpha: .55,
                        ),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Rejoignez-nous !',
                                  style: theme.textTheme.titleLarge,
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Tous vos services du quotidien, au même endroit.',
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.home_work_outlined,
                            size: 56,
                            color: theme.colorScheme.primary,
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
                        onPressed: auth.isLoading || _verificationEnCours ? null : _register,
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
            Text(label, style: TextStyle(color: selected ? color : null)),
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
