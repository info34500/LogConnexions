# LogConnexions

Deux scripts PowerShell, déployés par **GPO**, qui enregistrent l'utilisateur qui ouvre et ferme une session sur les postes d'un domaine Active Directory.

À chaque ouverture de session, une ligne est ajoutée dans un fichier CSV propre au poste ; à la fermeture, l'heure de déconnexion est complétée sur cette même ligne.

![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE?logo=powershell&logoColor=white)
![Windows](https://img.shields.io/badge/Windows-Active%20Directory-0078D6?logo=windows&logoColor=white)
![Licence](https://img.shields.io/badge/licence-MIT-green)

---

## Sommaire

- [Fonctionnement](#fonctionnement)
- [Contenu du dépôt](#contenu-du-dépôt)
- [Format des fichiers générés](#format-des-fichiers-générés)
- [Prérequis](#prérequis)
- [Installation](#installation)
  - [1. Créer le partage réseau](#1-créer-le-partage-réseau)
  - [2. Adapter les scripts](#2-adapter-les-scripts)
  - [3. Créer la GPO](#3-créer-la-gpo)
  - [4. Réglages recommandés](#4-réglages-recommandés)
  - [5. Tester](#5-tester)
- [Exploiter les journaux](#exploiter-les-journaux)
  - [Historique d'un utilisateur](#historique-dun-utilisateur)
  - [Autres requêtes utiles](#autres-requêtes-utiles)
- [Limites connues](#limites-connues)
- [Dépannage](#dépannage)
- [Licence](#licence)

---

## Fonctionnement

```
 Ouverture de session                         Fermeture de session
 ─────────────────────                        ─────────────────────
 Log-Connexion.ps1                            Log-Deconnexion.ps1
        │                                             │
        │  ajoute une ligne                           │  retrouve la dernière ligne
        │  Poste;Utilisateur;Date;Heure;              │  de l'utilisateur sans heure
        ▼                                             │  de déconnexion et la complète
 \\SERVEUR\LogsConnexions$\<NomDuPoste>.csv ◄─────────┘
```

| Script | Déclencheur GPO | Rôle |
|---|---|---|
| `Log-Connexion.ps1` | Ouverture de session | Crée `<NomDuPoste>.csv` s'il n'existe pas (avec l'en-tête), puis ajoute une ligne : poste, `DOMAINE\utilisateur`, date, heure. La colonne `Deconnexion` reste vide. |
| `Log-Deconnexion.ps1` | Fermeture de session | Cherche, en partant de la fin du fichier, la dernière ligne de l'utilisateur sans heure de déconnexion et y inscrit l'heure. Jusqu'à 10 tentatives si le fichier est momentanément verrouillé. |

Les deux scripts sont **silencieux** : si le partage est indisponible, ils échouent sans bloquer ni ralentir l'ouverture ou la fermeture de session.

## Contenu du dépôt

```
LogConnexions/
├── scripts/                       # déployés par GPO sur les postes
│   ├── Log-Connexion.ps1          # script d'ouverture de session
│   └── Log-Deconnexion.ps1        # script de fermeture de session
├── outils/                        # lancés à la main par l'administrateur
│   └── Historique-Utilisateur.ps1 # historique d'un utilisateur sur tous les postes
├── .gitattributes                 # fins de ligne CRLF pour les .ps1
├── .gitignore
├── LICENSE
└── README.md
```

## Format des fichiers générés

Un fichier par poste, nommé `<NomDuPoste>.csv`, encodé en UTF-8 avec BOM, séparateur `;` (s'ouvre directement dans Excel en version française).

```csv
Poste;Utilisateur;Date;Heure;Deconnexion
PC-COMPTA-01;CONTOSO\jdupont;19/10/2026;08:42:13;12:05:47
PC-COMPTA-01;CONTOSO\mmartin;19/10/2026;13:30:02;17:48:21
PC-COMPTA-01;CONTOSO\jdupont;20/10/2026;08:39:55;
```

> Une colonne `Deconnexion` vide signifie que la session est toujours ouverte, ou que la fermeture n'a pas pu être enregistrée (voir [Limites connues](#limites-connues)).

## Prérequis

- Un domaine Active Directory et la console **Gestion des stratégies de groupe** (GPMC).
- Des postes clients sous Windows 10 / 11 (Windows PowerShell 5.1, présent par défaut).
- Un serveur de fichiers accessible par tous les postes.

## Installation

### 1. Créer le partage réseau

Sur le serveur de fichiers, créez un dossier (par exemple `D:\LogsConnexions`) et partagez-le sous le nom **`LogsConnexions$`** (le `$` masque le partage dans le voisinage réseau).

**Autorisations de partage**

| Compte | Droit |
|---|---|
| Utilisateurs authentifiés | Modifier |
| Administrateurs | Contrôle total |

**Autorisations NTFS** (onglet *Sécurité* → *Avancé*, désactiver l'héritage)

| Compte | Droit | S'applique à |
|---|---|---|
| Administrateurs | Contrôle total | Ce dossier, les sous-dossiers et les fichiers |
| SYSTEM | Contrôle total | Ce dossier, les sous-dossiers et les fichiers |
| Utilisateurs authentifiés | Créer des fichiers / Écrire des données, Lister le dossier / Lire des données, Lire les attributs | Ce dossier uniquement |
| Utilisateurs authentifiés | Lecture, Écriture | Les fichiers uniquement |

> Les scripts s'exécutent **dans le contexte de l'utilisateur** : chaque utilisateur doit pouvoir créer et modifier les fichiers CSV. Évitez de lui accorder le droit *Supprimer*.

Le même résultat en PowerShell (à lancer en administrateur sur le serveur) :

```powershell
New-Item -Path 'D:\LogsConnexions' -ItemType Directory
New-SmbShare -Name 'LogsConnexions$' -Path 'D:\LogsConnexions' `
    -ChangeAccess 'Utilisateurs authentifiés' -FullAccess 'Administrateurs'
```

### 2. Adapter les scripts

Dans **les deux scripts**, remplacez `SERVEUR` par le nom de votre serveur de fichiers :

```powershell
# A ADAPTER : partage réseau qui contiendra les fichiers (un fichier par poste)
$Partage = "\\SERVEUR\LogsConnexions$"
```

> Le chemin doit être **identique** dans `Log-Connexion.ps1` et `Log-Deconnexion.ps1`.

### 3. Créer la GPO

1. Ouvrez la **Gestion des stratégies de groupe** (`gpmc.msc`).
2. Créez une GPO (par ex. `U - Journal des connexions`) et liez-la à l'**OU contenant les utilisateurs** à suivre.
   > Ce sont des scripts de **Configuration utilisateur** : la GPO doit s'appliquer aux *comptes utilisateurs*, pas aux ordinateurs. Pour cibler des postes plutôt que des personnes, liez-la à l'OU des ordinateurs et activez le *traitement en boucle de rappel* (voir étape 4).
3. Modifiez la GPO et allez dans :
   `Configuration utilisateur` → `Stratégies` → `Paramètres Windows` → `Scripts (ouverture/fermeture de session)`
4. Double-cliquez sur **Ouverture de session** → onglet **Scripts PowerShell** → **Afficher les fichiers…**
   Copiez-y `Log-Connexion.ps1`, fermez l'explorateur, puis **Ajouter…** → sélectionnez `Log-Connexion.ps1` → **OK**.
5. Faites de même avec **Fermeture de session** et `Log-Deconnexion.ps1`.

Les scripts sont ainsi stockés dans le SYSVOL de la GPO et répliqués sur tous les contrôleurs de domaine.

### 4. Réglages recommandés

Dans la même GPO (ou une GPO ordinateur) :

| Paramètre | Chemin | Valeur | Pourquoi |
|---|---|---|---|
| **Configurer le délai du script d'ouverture de session** | Config. ordinateur → Modèles d'administration → Système → Stratégie de groupe | Activé, **0** minute | Par défaut, Windows 8 et suivants attendent **5 minutes** avant de lancer les scripts d'ouverture de session : l'heure enregistrée serait décalée. |
| **Toujours attendre le réseau lors du démarrage de l'ordinateur et de l'ouverture de session** | Config. ordinateur → Modèles d'administration → Système → Ouverture de session | Activé | Garantit que le partage est joignable au moment de l'ouverture de session. |
| **Activer l'exécution des scripts** | Config. ordinateur → Modèles d'administration → Composants Windows → Windows PowerShell | Activé — *Autoriser les scripts locaux et les scripts signés distants* | Évite que la stratégie d'exécution bloque les scripts. |
| *(optionnel)* **Configurer le mode de traitement par bouclage de la stratégie de groupe utilisateur** | Config. ordinateur → Modèles d'administration → Système → Stratégie de groupe | Activé — *Fusion* | Uniquement si la GPO est liée à une OU d'**ordinateurs**. |

### 5. Tester

Sur un poste client :

```powershell
gpupdate /force
```

Fermez la session, rouvrez-la, puis vérifiez :

```powershell
Get-Content "\\SERVEUR\LogsConnexions$\$env:COMPUTERNAME.csv"
```

Une ligne avec votre nom, la date et l'heure doit apparaître. Fermez la session : l'heure de déconnexion est ajoutée sur cette même ligne.

## Exploiter les journaux

> Le dossier `outils/` contient des scripts à lancer **à la main**, depuis un poste d'administration. Ils ne doivent pas être ajoutés à la GPO.

### Historique d'un utilisateur

`outils/Historique-Utilisateur.ps1` parcourt tous les fichiers `<NomDuPoste>.csv` du partage, garde les lignes de l'utilisateur demandé et produit un CSV trié **de la connexion la plus récente à la plus ancienne**.

**Paramètres**

| Paramètre | Obligatoire | Description |
|---|---|---|
| `-Utilisateur` | oui | Login (`jdupont`), login avec domaine (`CONTOSO\jdupont`) ou motif avec jokers (`dupont*`). |
| `-Racine` | non | Partage contenant les CSV. Par défaut `\\SERVEUR\LogsConnexions$` — **à adapter** dans le script, comme pour les deux autres. |
| `-Sortie` | non | Fichier CSV à produire. Par défaut `Historique_<login>.csv` dans le dossier courant (écrasé à chaque exécution). |

**Exemples**

```powershell
# Historique de jdupont -> .\Historique_jdupont.csv
.\Historique-Utilisateur.ps1 -Utilisateur jdupont

# Avec le domaine et un fichier de sortie choisi
.\Historique-Utilisateur.ps1 -Utilisateur "CONTOSO\jdupont" -Sortie C:\Temp\jdupont.csv

# Tous les comptes commençant par "dupont"
.\Historique-Utilisateur.ps1 -Utilisateur "dupont*"
```

Résultat affiché :

```
12 connexion(s) trouvée(s) sur 3 poste(s) -> C:\Temp\jdupont.csv
```

Le fichier produit a les mêmes colonnes que les journaux (`Poste;Utilisateur;Date;Heure;Deconnexion`) et s'ouvre directement dans Excel.

> Il faut un compte ayant le droit de **lecture** sur le partage. Si la stratégie d'exécution bloque le script : `powershell -ExecutionPolicy Bypass -File .\Historique-Utilisateur.ps1 -Utilisateur jdupont`.

### Autres requêtes utiles

**Fusionner tous les postes dans un seul fichier**

```powershell
Get-ChildItem '\\SERVEUR\LogsConnexions$\*.csv' |
    ForEach-Object { Import-Csv $_.FullName -Delimiter ';' -Encoding UTF8 } |
    Export-Csv 'C:\Temp\Connexions-Tous-Postes.csv' -Delimiter ';' -NoTypeInformation -Encoding UTF8
```

**Sessions encore ouvertes (ou non clôturées)**

```powershell
Get-ChildItem '\\SERVEUR\LogsConnexions$\*.csv' |
    ForEach-Object { Import-Csv $_.FullName -Delimiter ';' -Encoding UTF8 } |
    Where-Object { -not $_.Deconnexion } |
    Format-Table -AutoSize
```

## Limites connues

- **Coupure brutale** (coupure de courant, écran bleu, arrêt forcé) : le script de fermeture ne s'exécute pas, la colonne `Deconnexion` reste vide.
- **Verrouillage / déverrouillage** et **changement rapide d'utilisateur** ne sont pas des ouvertures ou fermetures de session : ils ne sont pas enregistrés.
- **Session à cheval sur minuit** : seule l'heure de déconnexion est enregistrée, pas sa date.
- **Postes hors réseau** (portables en déplacement sans VPN) : rien n'est enregistré tant que le partage est injoignable.
- **Connexions Bureau à distance (RDP)** : enregistrées comme une ouverture de session ordinaire sur le poste distant.
- Les fichiers grossissent indéfiniment : prévoyez un archivage périodique (par exemple, renommer les fichiers chaque mois).

## Dépannage

| Symptôme | Piste |
|---|---|
| Aucun fichier n'est créé | Vérifiez que la GPO s'applique à l'utilisateur : `gpresult /r /scope user`. Vérifiez les droits d'écriture de l'utilisateur sur le partage. |
| L'heure d'ouverture est décalée d'environ 5 minutes | Réglez *Configurer le délai du script d'ouverture de session* sur 0 (étape 4). |
| La colonne `Deconnexion` n'est jamais remplie | Vérifiez que `Log-Deconnexion.ps1` est bien dans l'onglet **Scripts PowerShell** de *Fermeture de session*, et que le chemin `$Partage` est identique dans les deux scripts. |
| Les scripts ne s'exécutent pas | Vérifiez la stratégie d'exécution PowerShell (étape 4). Testez à la main : `powershell -ExecutionPolicy Bypass -File .\Log-Connexion.ps1`. |
| Accents mal affichés dans Excel | Ouvrez le CSV via *Données* → *À partir d'un fichier texte/CSV* et choisissez l'encodage *65001 : Unicode (UTF-8)*. |

## Licence

Distribué sous licence [MIT](LICENSE).
