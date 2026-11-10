enum TypeTrajetEnum { offre, demande }

enum StatutTrajetEnum { ouvert, complet, termine, annule }

enum StatutReservationEnum { enAttente, confirmee, refusee, annulee }

enum TypeNotificationEnum {
  nouvelleDemandeZone,
  reservationRecue,
  propositionRecue,
  confirmation,
  refus,
  annulation,
  rappelDepart,
  alerteTrajet,
}

enum CreneauAlerteEnum { matin, apresMidi, soir, journee }

extension CovoiturageLabels on TypeTrajetEnum {
  String get libelle => this == TypeTrajetEnum.offre ? 'Offre' : 'Demande';
}

extension StatutTrajetLabel on StatutTrajetEnum {
  String get libelle => switch (this) {
    StatutTrajetEnum.ouvert => 'Ouvert',
    StatutTrajetEnum.complet => 'Complet',
    StatutTrajetEnum.termine => 'Terminé',
    StatutTrajetEnum.annule => 'Annulé',
  };
}

extension StatutReservationLabel on StatutReservationEnum {
  String get libelle => switch (this) {
    StatutReservationEnum.enAttente => 'En attente',
    StatutReservationEnum.confirmee => 'Confirmée',
    StatutReservationEnum.refusee => 'Refusée',
    StatutReservationEnum.annulee => 'Annulée',
  };
}
