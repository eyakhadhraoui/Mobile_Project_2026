import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/utils/validators.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/welcome_email_service.dart';

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

  @override
  void dispose() {
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
      await auth.register(
        user: user,
        password: _passwordController.text,
      );
      final mailService = const WelcomeEmailService();
      final emailStatus = await mailService.sendWelcome(
        email: user.email,
        firstName: user.prenom,
      );
      if (!mounted) return;
      var verified = false;
      if (emailStatus == WelcomeEmailStatus.sent) {
        verified = (await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (_) => _EmailVerificationDialog(email: user.email, firstName: user.prenom, service: mailService),
        )) ?? false;
        if (verified && mounted) await auth.markEmailVerified(user.id);
      }
      if (mounted) await auth.signOut();
      final emailMessage = switch (emailStatus) {
        WelcomeEmailStatus.sent => verified
            ? 'Adresse e-mail vérifiée. Votre compte attend maintenant la validation de l’administrateur.'
            : 'Le code n’a pas été confirmé. Vous pourrez refaire l’inscription après activation du renvoi de code.',
        WelcomeEmailStatus.notConfigured =>
          'Compte créé, mais le service e-mail n’est pas configuré. Configurez le serveur pour vérifier l’adresse.',
        _ => 'Le compte est créé, mais le code de vérification n’a pas pu être envoyé.',
      };
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Compte créé'),
          content: Text(emailMessage),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Continuer'),
            ),
          ],
        ),
      );
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      final message =
          context.read<AuthProvider>().error ?? 'Inscription impossible.';
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
                      validator: (value) {
                        if (value == null || value.length < 8) {
                          return 'Utilisez au moins 8 caractères.';
                        }
                        return null;
                      },
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
                        onPressed: auth.isLoading ? null : _register,
                        child: auth.isLoading
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

class _EmailVerificationDialog extends StatefulWidget {
  const _EmailVerificationDialog({required this.email, required this.firstName, required this.service});
  final String email;
  final String firstName;
  final WelcomeEmailService service;

  @override
  State<_EmailVerificationDialog> createState() => _EmailVerificationDialogState();
}

class _EmailVerificationDialogState extends State<_EmailVerificationDialog> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() { _code.dispose(); super.dispose(); }

  Future<void> _verify() async {
    if (_code.text.trim().length != 6) { setState(() => _error = 'Saisissez le code à 6 chiffres.'); return; }
    setState(() { _busy = true; _error = null; });
    final result = await widget.service.verifyCode(email: widget.email, code: _code.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = result == WelcomeEmailStatus.invalidCode ? 'Code incorrect ou expiré.' : result == WelcomeEmailStatus.verified ? null : 'Vérification indisponible. Réessayez.';
    });
    if (result == WelcomeEmailStatus.verified) Navigator.of(context).pop(true);
  }

  Future<void> _resend() async {
    setState(() { _busy = true; _error = null; });
    final result = await widget.service.sendWelcome(email: widget.email, firstName: widget.firstName);
    if (!mounted) return;
    setState(() { _busy = false; _error = result == WelcomeEmailStatus.sent ? 'Nouveau code envoyé.' : 'Impossible de renvoyer le code.'; });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Vérifiez votre e-mail'),
    content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Saisissez le code envoyé à ${widget.email}.'),
      const SizedBox(height: 12),
      TextField(controller: _code, keyboardType: TextInputType.number, maxLength: 6, decoration: const InputDecoration(labelText: 'Code à 6 chiffres')),
      if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      TextButton(onPressed: _busy ? null : _resend, child: const Text('Renvoyer le code')),
    ]),
    actions: [
      TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(false), child: const Text('Plus tard')),
      FilledButton(onPressed: _busy ? null : _verify, child: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Vérifier')),
    ],
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
