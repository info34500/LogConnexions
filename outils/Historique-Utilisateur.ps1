<#
.SYNOPSIS
    Recherche un utilisateur dans les CSV de connexion des postes et produit son historique.

.DESCRIPTION
    Lit tous les fichiers <NomDuPoste>.csv du partage (créés par Log-Connexion.ps1 / Log-Deconnexion.ps1, colonnes Poste;Utilisateur;Date;Heure;Deconnexion),
    garde les lignes de l'utilisateur demandé et écrit un CSV trié de la connexion la plus récente à la plus ancienne.

.EXAMPLE
    .\Historique-Utilisateur.ps1 -Utilisateur jdupont

.EXAMPLE
    .\Historique-Utilisateur.ps1 -Utilisateur "MONDOMAINE\jdupont" -Sortie C:\Temp\jdupont.csv

.EXAMPLE
    .\Historique-Utilisateur.ps1 -Utilisateur "dupont*"      # jokers acceptés
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$Utilisateur,

    # A ADAPTER : partage où Log-Connexion.ps1 écrit les fichiers (un CSV par poste)
    [string]$Racine = "\\SERVEUR\LogsConnexions$",

    # Fichier de sortie (par défaut : Historique_<login>.csv dans le dossier courant)
    [string]$Sortie
)

if (-not (Test-Path -LiteralPath $Racine)) {
    Write-Error "Dossier introuvable : $Racine"
    exit 1
}

# Un seul fichier par utilisateur : nom fixe Historique_<login>.csv, réécrit à chaque exécution
# ("jdupont" et "MONDOMAINE\jdupont" donnent le même fichier)
if (-not $Sortie) {
    $loginSortie = ($Utilisateur -split '\\')[-1]
    $nomSur = $loginSortie -replace '[\\/:*?"<>|]', '_'
    $Sortie = Join-Path (Get-Location) ("Historique_{0}.csv" -f $nomSur)
}

$culture  = [System.Globalization.CultureInfo]::InvariantCulture
$resultat = New-Object System.Collections.Generic.List[object]

# Un CSV par poste, à la racine du partage (on ignore d'éventuels fichiers d'historique déjà générés)
$fichiers = Get-ChildItem -LiteralPath $Racine -Filter *.csv -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notlike 'Historique_*' }

foreach ($f in $fichiers) {
    try { $lignes = Import-Csv -LiteralPath $f.FullName -Delimiter ';' -Encoding UTF8 -ErrorAction Stop } catch { continue }

    foreach ($l in $lignes) {
        if (-not $l.Utilisateur) { continue }
        $login = ($l.Utilisateur -split '\\')[-1]
        if (($login -notlike $Utilisateur) -and ($l.Utilisateur -notlike $Utilisateur)) { continue }

        $dt = [datetime]::MinValue
        [void][datetime]::TryParseExact("$($l.Date) $($l.Heure)", 'dd/MM/yyyy HH:mm:ss', $culture, 'None', [ref]$dt)

        $poste = if ($l.Poste) { $l.Poste } else { $f.BaseName }
        $resultat.Add([pscustomobject]@{
            Poste       = $poste
            Utilisateur = $l.Utilisateur
            Date        = $l.Date
            Heure       = $l.Heure
            Deconnexion = $l.Deconnexion
            _Tri        = $dt
        })
    }
}

if ($resultat.Count -eq 0) {
    Write-Warning "Aucune connexion trouvée pour '$Utilisateur' dans $Racine"
    exit 0
}

# Plus récente en haut
$resultat |
    Sort-Object _Tri -Descending |
    Select-Object Poste, Utilisateur, Date, Heure, Deconnexion |
    Export-Csv -LiteralPath $Sortie -Delimiter ';' -NoTypeInformation -Encoding UTF8

Write-Host ("{0} connexion(s) trouvée(s) sur {1} poste(s) -> {2}" -f $resultat.Count, ($resultat | Select-Object -ExpandProperty Poste -Unique).Count, $Sortie)
