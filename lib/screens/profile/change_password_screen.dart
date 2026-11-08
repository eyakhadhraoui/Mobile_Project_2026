import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/utils/validators.dart';
import '../../providers/auth_provider.dart';
import '../../providers/mot_de_passe_provider.dart';
import '../../widgets/indicateur_mot_de_passe.dart';

/// Changement du mot de passe du compte connecté, avec indicateur de force et
/// vérification des fuites de données (Pwned Passwords).
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _ancienController = TextEditingController();
  final _nouveauController = TextEditingController();
  final _confirmationController = TextEditingController();
  final _verification = MotDePasseProvider();
  bool _masquer = true;
  bool _envoi = false;

  @override
  void dispose() {
    _verification.dispose();
    _ancienController.dispose();
    _nouveauController.dispose();
    _confirmationController.dispose();
    super.dispose();
  }

  Future<void> _enregistrer() async {
    if (_envoi || !_formKey.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    setState(() => _envoi = true);
    try {
      if (!await autoriserMotDePasse(context, _verification, _nouveauController.text)) return;
      final serveurAJour = await auth.changePassword(
        ancien: _ancienController.text,
        nouveau: _nouveauController.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            serveurAJour
                ? 'Mot de passe modifié.'
                : 'Mot de passe modifié sur cet appareil. Le serveur sera mis à jour à votre '
                      'prochaine connexion (confirmation par e-mail).',
          ),
        ),
      );
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Changer le mot de passe')),
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
                  _label('Mot de passe actuel'),
                  TextFormField(
                    controller: _ancienController,
                    obscureText: _masquer,
                    textInputAction: TextInputAction.next,
                    decoration: _decoration('Votre mot de passe actuel'),
                    validator: (value) => Validators.required(value, label: 'Le mot de passe actuel'),
                  ),
                  const SizedBox(height: 16),
                  _label('Nouveau mot de passe'),
                  TextFormField(
                    key: const Key('nouveauMotDePasse'),
                    controller: _nouveauController,
                    obscureText: _masquer,
                    textInputAction: TextInputAction.next,
                    decoration: _decoration('$longueurMinimaleMotDePasse caractères minimum'),
                    onChanged: _verification.surSaisie,
                    validator: (value) {
                      final erreur = Validators.nouveauMotDePasse(value);
                      if (erreur != null) return erreur;
                      return value == _ancienController.text ? 'Choisissez un mot de passe différent de l’actuel.' : null;
                    },
                  ),
                  ChangeNotifierProvider.value(value: _verification, child: const IndicateurMotDePasse()),
                  const SizedBox(height: 16),
                  _label('Confirmer le nouveau mot de passe'),
                  TextFormField(
                    controller: _confirmationController,
                    obscureText: _masquer,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _enregistrer(),
                    decoration: _decoration('Répétez le nouveau mot de passe'),
                    validator: (value) =>
                        value != _nouveauController.text ? 'Les mots de passe ne correspondent pas.' : null,
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _envoi ? null : _enregistrer,
                    child: _envoi
                        ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Enregistrer'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );

  InputDecoration _decoration(String hint) => InputDecoration(
    prefixIcon: const Icon(Icons.lock_outline),
    hintText: hint,
    suffixIcon: IconButton(
      tooltip: _masquer ? 'Afficher' : 'Masquer',
      onPressed: () => setState(() => _masquer = !_masquer),
      icon: Icon(_masquer ? Icons.visibility_outlined : Icons.visibility_off_outlined),
    ),
  );

  Widget _label(String label) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(label, style: Theme.of(context).textTheme.labelLarge),
  );
}
