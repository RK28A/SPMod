# Fonctionnalités de SPMod

Toutes les options se trouvent dans **Réglages Spotify → SPModulation**.

Légende : 🟢 ajouté par SPMod · 🔵 repris du projet de base (EeveeSpotifyReborn) · 🟡 en préparation

---

## Premium

| | Fonctionnalité | Description |
|---|---|---|
| 🔵 | Premium dynamique | Intercepte les données de compte envoyées par Spotify et les modifie en temps réel pour débloquer les fonctions Premium côté app (lecture dans l'ordre, sauts illimités, pas de pubs audio). |
| 🔵 | Ne pas patcher Premium | Désactive le patch si tu as un vrai abonnement. Détecté automatiquement au premier lancement. |
| 🔵 | Écraser la configuration | Remplace la configuration distante par une configuration Premium enregistrée, qui contrôle une grande partie de l'interface. |
| 🔵 | Titres likés sur les pages artiste | Ajoute la ligne « Titres likés » et la liste complète des titres sur les pages artiste. |
| 🔵 | Siri sans « mode radio » | Siri lance le titre ou la playlist demandé au lieu d'une radio. |
| 🔵 | Rappels des limites serveur | Explique pourquoi la très haute qualité audio et le téléchargement natif de playlists ne fonctionnent pas. |

## Paroles

| | Fonctionnalité | Description |
|---|---|---|
| 🔵 | Sources de paroles | Genius, LRCLIB (serveur personnalisable), Musixmatch (token ou token anonyme) et PetitLyrics. |
| 🔵 | Paroles pour tous les titres | La carte des paroles apparaît même sur les titres où Spotify n'en propose pas. |
| 🔵 | Paroles romanisées | Japonais, coréen et chinois en alphabet latin. |
| 🔵 | Langue Musixmatch | Traductions Musixmatch quand elles existent. |
| 🔵 | Masquer en cas d'erreur | Retire la carte des paroles si le chargement échoue. |
| 🔵 | Raison du repli | Affiche sous les paroles pourquoi une source de secours a été utilisée. |
| 🟢 | Sources de secours ordonnées | Choisis quelles sources essayer et dans quel ordre si la principale échoue. |
| 🟢 | Cache des paroles | Les paroles chargées sont gardées 30 jours sur l'appareil : ouverture plus rapide et utilisables hors ligne. |
| 🟢 | Traduction des paroles | Traduction sur l'appareil avec Apple Traduction (iOS 18+), avec secours en ligne seulement si tu l'autorises. Modes « original + traduction » ou « traduction seule », synchronisation conservée ligne par ligne, cache des traductions. |
| 🟡 | Taille du texte des paroles | En attente de l'analyse de l'IPA. |

## Lecture

| | Fonctionnalité | Description |
|---|---|---|
| 🟢 | Garder l'écran allumé | L'écran reste allumé pendant la lecture quand des paroles sont visibles. Activé par défaut. |
| 🟢 | Désactiver les Canvas | Bloque les vidéos Canvas du lecteur pour économiser batterie et données. Désactivé par défaut. |
| 🟢 | Secouer pour copier | Secoue le téléphone pour copier le titre en cours : lien, titre – artiste, les deux ou l'ID. |
| 🔵 | Ouvrir les liens dans l'app | Compatible avec l'extension Safari OpenSpotifySafariExtension (intégrée à l'IPA si l'option est cochée dans le workflow). |
| 🟡 | Smart Shuffle amélioré | Modes pur, sans répétition, variété, découverte et favoris. En attente de l'IPA. |
| 🟡 | Ajout rapide à la dernière playlist | Bouton dans le lecteur, playlist épinglable, anti-doublons. En attente de l'IPA. |

## Statistiques et historique

| | Fonctionnalité | Description |
|---|---|---|
| 🟢 | Statistiques d'écoute | Temps d'écoute, lectures, titres, artistes et albums différents, moyenne par jour, sessions. Périodes : aujourd'hui, hier, 7 jours, 30 jours, mois, année, depuis l'installation, personnalisée. Comparaison avec la période précédente. |
| 🟢 | Graphiques | Écoute par jour, évolution, heures de la journée, répartition par artiste. |
| 🟢 | Tops 10 / 25 / 50 / 100 | Titres, artistes et albums avec pochette, lectures, temps cumulé et pourcentage, et une fiche détaillée pour chacun. |
| 🟢 | Historique d'écoute | Chronologie groupée par jour, semaine ou mois, recherche, filtres, calendrier, ouverture du titre dans Spotify, suppression d'une entrée, d'une période ou de tout. |
| 🟢 | Export / import | JSON et CSV. Seul le temps réellement écouté sur l'appareil est compté, sans doublons. La collecte peut être coupée. |

## Apparence

| | Fonctionnalité | Description |
|---|---|---|
| 🟢 | Thèmes | Spotify, AMOLED, Minuit, Violet, Forêt, Coucher de soleil, Rose et Personnalisé (fond, surfaces, accent). Aperçu en direct. |
| 🟢 | Couleur d'accent | Remplace le vert de Spotify par la couleur de ton choix, par-dessus n'importe quel thème. |
| 🟢 | Mode nuit | Toujours actif, sur horaires ou selon le mode sombre d'iOS, avec thème de nuit, accent atténué et animations plus courtes. Appliqué au prochain lancement. |
| 🔵 | Couleurs des paroles | Couleurs d'origine, couleur fixe ou couleur tirée de la pochette avec facteur de normalisation. |
| 🔵 | Popups sombres | Popups de Spotify en mode sombre. |
| 🟡 | Masquer des sections de l'accueil | En attente de l'IPA. |
| 🟡 | Masquer les boutons Premium | En attente de l'IPA. |

## Confidentialité

| | Fonctionnalité | Description |
|---|---|---|
| 🟢 | Protection des données | Niveaux désactivé, standard, renforcé ou personnalisé. Catégories : mesure publicitaire, analytique tierce, attribution, diagnostics facultatifs, marketing, télémétrie Spotify. Les requêtes nécessaires à la connexion, la lecture, la synchronisation et les playlists ne sont jamais bloquées. |
| 🟢 | Tableau de bord | Nombre de requêtes bloquées par catégorie et date du dernier blocage. |
| 🟢 | Données locales | Suppression de l'historique, des stats, du cache des paroles et traductions, désactivation des journaux SPMod. |

## Réglages et sauvegarde

| | Fonctionnalité | Description |
|---|---|---|
| 🟢 | SPModulation | Menu réorganisé par catégories : Général, Musique, Apparence, Avancé. |
| 🟢 | Langue | Automatique, English ou Français, modifiable dans Général. |
| 🟢 | Sauvegarde automatique | Réglages gardés dans le trousseau iOS, et réglages + stats + historique enregistrés dans un dossier de l'app Fichiers (Sur mon iPhone ou iCloud Drive) à chaque fois que tu quittes Spotify. Après l'installation d'une nouvelle version, SPMod propose de tout restaurer. Format versionné et lu de façon tolérante pour rester compatible avec les versions futures. |
| 🟢 | Export / import des réglages | Fichier .plist partageable (contient le token Musixmatch). |
| 🟢 | Réinitialisation sécurisée | Trois confirmations avant d'effacer les données de Spotify. |
| 🔵 | Vérification de mise à jour | Compare ta version à la dernière release de SPMod. |
| 🔵 | Expériences | Partage vers Instagram toujours visible, partage vers LiveContainer. |

## Stabilité

| | Fonctionnalité | Description |
|---|---|---|
| 🟢 | Corrections de plantages | Suppression des déballages forcés risqués, protection des index, conversions de couleurs bornées, requêtes réseau toujours terminées, tampon réseau protégé entre threads. |
| 🔵 | Correctif de défilement des paroles | Évite un plantage connu lors du défilement des paroles. |

---

## Workflow « Create SPMod IPA »

Compile le tweak depuis le code de ce repo, l'injecte dans ton IPA Spotify décryptée avec SwiftProtobuf et l'extension Safari, puis publie une release brouillon avec l'IPA (et une version patchée si l'option est cochée). Paramètres : lien de l'IPA, extension Safari, IPA patchée, nom de l'app, bundle ID.
