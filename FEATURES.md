# Fonctionnalités de SPMod

Toutes les options se trouvent dans **Réglages Spotify → SPModulation**.

Légende : 🟢 ajouté par SPMod · 🔵 repris du projet de base (EeveeSpotifyReborn) · 🟡 en préparation

---

## Premium

| | Fonctionnalité | Description |
|---|---|---|
| 🔵 | Premium dynamique | Intercepte les données de compte envoyées par Spotify et les modifie en temps réel pour débloquer les fonctions Premium côté app (lecture dans l'ordre, sauts illimités, pas de pubs audio). |
| 🟢 | Patch Premium au niveau product state | Force les attributs du compte (ads, catalogue, type, on-demand…) directement là où l'app les lit, pour que le Premium et le blocage des pubs s'appliquent même quand Spotify change son transport réseau (cas de la 9.1+). |
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
| 🔵 | Paroles pour tous les titres (9.1+) | Rétabli sur les versions récentes en forçant les interrupteurs internes de Spotify. |

## Lecture

| | Fonctionnalité | Description |
|---|---|---|
| 🟢 | Garder l'écran allumé | L'écran reste allumé pendant la lecture quand des paroles sont visibles. Activé par défaut. |
| 🟢 | Désactiver les Canvas | Coupe les Canvas via l'interrupteur interne de Spotify, avec blocage réseau en secours. Désactivé par défaut. |
| 🟢 | Secouer pour copier | Secoue le téléphone pour copier le titre en cours : lien, titre – artiste, les deux ou l'ID. |
| 🔵 | Ouvrir les liens dans l'app | Compatible avec l'extension Safari OpenSpotifySafariExtension (intégrée à l'IPA si l'option est cochée dans le workflow). |
| 🟢 | Smart Shuffle (expérimental) | Modes pur, sans répétition, variété, découverte et favoris, écart minimum entre un même artiste, exclusion des titres récents, niveau d'aléatoire. Ne modifie jamais l'ordre des playlists. |
| 🟢 | Ajout rapide (expérimental) | Ajoute le titre en cours à la playlist épinglée ou à la dernière utilisée, en secouant le téléphone ou depuis SPModulation. Anti-doublons, confirmation avec le nom de la playlist. |

## Playlists (expérimental)

| | Fonctionnalité | Description |
|---|---|---|
| 🟢 | Gestionnaire de playlists | Doublons (en gardant une occurrence), tri par titre, artiste, album, durée, date d'ajout, année ou aléatoire, recherche et filtre par artiste, sélection multiple pour copier, déplacer, retirer ou créer une nouvelle playlist, aperçu avant confirmation, annulation de la dernière modification. |
| 🟢 | Fusion de playlists | Choix des playlists sources et de la destination, doublons ignorés en option. |
| ℹ️ | Fonctionnement | Utilise l'API Web officielle de Spotify avec la session de l'app. Si Spotify refuse, une erreur s'affiche et rien n'est modifié. |

## Statistiques et historique

| | Fonctionnalité | Description |
|---|---|---|
| 🟢 | Statistiques d'écoute | Temps d'écoute, lectures, titres, artistes et albums différents, moyenne par jour, sessions. Périodes : aujourd'hui, hier, 7 jours, 30 jours, mois, année, depuis l'installation, personnalisée. Comparaison avec la période précédente. |
| 🟢 | Graphiques | Écoute par jour, évolution, heures de la journée, répartition par artiste. |
| 🟢 | Tops 10 / 25 / 50 / 100 | Titres, artistes et albums avec pochette, lectures, temps cumulé et pourcentage, et une fiche détaillée pour chacun. |
| 🟢 | Historique d'écoute | Chronologie groupée par jour, semaine ou mois, recherche, filtres, calendrier, ouverture du titre dans Spotify, suppression d'une entrée, d'une période ou de tout. |
| 🟢 | Playlists depuis l'historique | Ajouter un titre de l'historique à une playlist, ou créer une playlist avec les résultats filtrés (expérimental). |
| 🟢 | Export / import | JSON et CSV. Seul le temps réellement écouté sur l'appareil est compté, sans doublons. La collecte peut être coupée. |

## Apparence

| | Fonctionnalité | Description |
|---|---|---|
| 🟢 | Thèmes | Spotify, AMOLED, Minuit, Violet, Forêt, Coucher de soleil, Rose et Personnalisé (fond, surfaces, accent). Aperçu en direct. |
| 🟢 | Couleur d'accent | Remplace le vert de Spotify par la couleur de ton choix, par-dessus n'importe quel thème. |
| 🟢 | Mode nuit | Toujours actif, sur horaires ou selon le mode sombre d'iOS, avec thème de nuit, accent atténué et animations plus courtes. Appliqué au prochain lancement. |
| 🔵 | Couleurs des paroles | Couleurs d'origine, couleur fixe ou couleur tirée de la pochette avec facteur de normalisation. |
| 🔵 | Popups sombres | Popups de Spotify en mode sombre. |
| 🟢 | Masquer les bannières Premium | Masque les bannières qui proposent de passer à Premium. Activé par défaut. |

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
| 🟢 | Hooks tolérants | Si une partie du tweak ne correspond pas à la version de Spotify installée, elle est ignorée au lieu de faire planter l'app au lancement. |
| 🟢 | Diagnostic | Général → Diagnostic : versions, liste des hooks ignorés et rapport à copier. |
| 🟢 | Accès à SPModulation sur Spotify 9.1+ | Bouton « SPMod » dans les réglages de Spotify (le menu d'origine n'existe plus dans les versions récentes). |

---

## Workflow « Create SPMod IPA »

Compile le tweak depuis le code de ce repo, l'injecte dans ton IPA Spotify décryptée avec SwiftProtobuf et l'extension Safari, puis publie une release brouillon avec l'IPA. Paramètres : lien de l'IPA, extension Safari, nom de l'app, bundle ID. L'IPA produite est déjà patchée avec ipapatch pour une meilleure compatibilité de sideload.

---

## Non réalisable

| Fonctionnalité | Raison |
|---|---|
| Masquer des sections de l'accueil | L'accueil des versions récentes est entièrement en Swift, sans point d'accroche fiable : le filtrage casserait la mise en page. |
| Taille du texte des paroles | Les lignes sont dessinées par le moteur de texte de Spotify : changer la police casse la mise en page et le défilement. |
| Style du texte traduit (taille, couleur) | L'affichage de la traduction est géré par Spotify. |
| Limite de volume du mode nuit | iOS n'autorise pas une app à changer le volume du système, et le volume du lecteur Spotify n'est pas accessible. |
| Changement de thème en direct | Les couleurs sont appliquées au chargement des écrans : le changement se fait au prochain lancement. |
| Bouton d'ajout rapide dans le lecteur | Le lecteur est en Swift sans point d'accroche : l'ajout rapide se fait en secouant le téléphone ou depuis SPModulation. |
| Ne pas compter les écoutes d'autres appareils | iOS ne distingue pas la lecture locale du contrôle à distance via Spotify Connect. |
