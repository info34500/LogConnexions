# Log-Connexion.ps1
# Script d'ouverture de session (GPO > Configuration utilisateur > Stratégies > Paramètres Windows > Scripts > Ouverture de session > onglet "Scripts PowerShell").
#
# Un fichier CSV par poste, nommé d'après le poste : <NomDuPoste>.csv
# Colonnes : Poste;Utilisateur;Date;Heure;Deconnexion
# La colonne Deconnexion est laissée vide ici : elle est complétée par Log-Deconnexion.ps1 à la fermeture de session.

# A ADAPTER : partage réseau qui contiendra les fichiers (un fichier par poste)
$Partage = "\\SERVEUR\LogsConnexions$"

$Poste      = $env:COMPUTERNAME
$Fichier    = Join-Path $Partage "$Poste.csv"
$Maintenant = Get-Date
$Ligne      = "{0};{1};{2};{3};" -f $Poste,
                                    "$env:USERDOMAIN\$env:USERNAME",
                                    $Maintenant.ToString("dd/MM/yyyy"),
                                    $Maintenant.ToString("HH:mm:ss")

try {
    # Premier passage sur ce poste : on écrit d'abord l'en-tête
    if (-not (Test-Path -LiteralPath $Fichier)) {
        Add-Content -LiteralPath $Fichier -Value "Poste;Utilisateur;Date;Heure;Deconnexion" -Encoding UTF8 -ErrorAction Stop
    }
    Add-Content -LiteralPath $Fichier -Value $Ligne -Encoding UTF8 -ErrorAction Stop
}
catch {
    # Ne jamais bloquer l'ouverture de session si le partage est indisponible
}
