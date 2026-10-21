enum UserRole { locataire, proprietaire, prestataire, administrateur }

enum AccountStatus { pending, approved, blocked }

class UserModel {
  const UserModel({
    required this.id,
    required this.nom,
    required this.prenom,
    required this.email,
    required this.telephone,
    required this.rolePrincipal,
    this.roleSecondaire,
    this.photo,
    this.preferences = const <String, dynamic>{},
    this.emailVerified = false,
    this.accountStatus = AccountStatus.pending,
  });

  final String id;
  final String nom;
  final String prenom;
  final String email;
  final String telephone;
  final UserRole rolePrincipal;
  final UserRole? roleSecondaire;
  final String? photo;
  final Map<String, dynamic> preferences;
  final bool emailVerified;
  final AccountStatus accountStatus;
}
