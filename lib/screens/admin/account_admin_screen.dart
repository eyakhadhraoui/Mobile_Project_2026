import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_client.dart';

class AccountAdminScreen extends StatefulWidget {
  const AccountAdminScreen({super.key});

  @override
  State<AccountAdminScreen> createState() => _AccountAdminScreenState();
}

class _AccountAdminScreenState extends State<AccountAdminScreen> {
  late Future<List<UserModel>> _users;
  String? _enCours;

  @override
  void initState() {
    super.initState();
    _users = context.read<AuthProvider>().getUsersForAdministration();
  }

  void _reload() {
    setState(() {
      _users = context.read<AuthProvider>().getUsersForAdministration();
    });
  }

  @override
  Widget build(BuildContext context) {
    final monId = context.read<AuthProvider>().currentUserId;
    return Scaffold(
      appBar: AppBar(title: const Text('Gestion des comptes')),
      body: FutureBuilder<List<UserModel>>(
        future: _users,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_erreur(snapshot.error!), textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _reload,
                      child: const Text('Réessayer'),
                    ),
                  ],
                ),
              ),
            );
          }
          final users = snapshot.data ?? [];
          if (users.isEmpty) {
            return const Center(child: Text('Aucun compte enregistré.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: users.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final user = users[index];
              final protege =
                  user.id == monId ||
                  user.rolePrincipal == UserRole.administrateur;
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${user.prenom} ${user.nom}'.trim(),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(user.email),
                      const SizedBox(height: 6),
                      Text(
                        '${_role(user.rolePrincipal)} · Compte : ${_status(user.accountStatus)}',
                      ),
                      if (!protege) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: [
                            if (user.accountStatus != AccountStatus.approved)
                              OutlinedButton.icon(
                                onPressed: _enCours == null
                                    ? () => _change(user, AccountStatus.approved)
                                    : null,
                                icon: const Icon(Icons.check),
                                label: const Text('Valider'),
                              ),
                            if (user.accountStatus != AccountStatus.blocked)
                              OutlinedButton.icon(
                                onPressed: _enCours == null
                                    ? () => _bloquer(user)
                                    : null,
                                icon: const Icon(Icons.block),
                                label: const Text('Bloquer'),
                              ),
                            if (user.accountStatus != AccountStatus.pending)
                              TextButton(
                                onPressed: _enCours == null
                                    ? () => _change(user, AccountStatus.pending)
                                    : null,
                                child: const Text('Remettre en attente'),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _bloquer(UserModel user) async {
    final confirme = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Bloquer ce compte ?'),
        content: Text(
          '${user.email} ne pourra plus se connecter et sa session sera fermée.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Bloquer'),
          ),
        ],
      ),
    );
    if (confirme == true) await _change(user, AccountStatus.blocked);
  }

  Future<void> _change(UserModel user, AccountStatus status) async {
    setState(() => _enCours = user.id);
    try {
      await context.read<AuthProvider>().setAccountStatus(user.id, status);
      if (!mounted) return;
      setState(() => _enCours = null);
      _reload();
    } catch (error) {
      if (!mounted) return;
      setState(() => _enCours = null);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_erreur(error))));
    }
  }

  String _erreur(Object error) =>
      error is ApiException ? error.message : 'Une erreur est survenue.';

  String _status(AccountStatus status) => switch (status) {
    AccountStatus.pending => 'en attente',
    AccountStatus.approved => 'validé',
    AccountStatus.blocked => 'bloqué',
  };

  String _role(UserRole role) => switch (role) {
    UserRole.locataire => 'Étudiant / locataire',
    UserRole.proprietaire => 'Propriétaire',
    UserRole.prestataire => 'Prestataire',
    UserRole.administrateur => 'Administrateur',
  };
}
