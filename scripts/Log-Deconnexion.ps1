# Log-Deconnexion.ps1
# Script de fermeture de session (GPO > Configuration utilisateur > Stratégies > Paramètres Windows > Scripts > Fermeture de session > onglet "Scripts PowerShell").
#
# Complète, dans <NomDuPoste>.csv, la colonne Deconnexion de la dernière ligne de l'utilisateur
# qui n'a pas encore d'heure de déconnexion (= la session qui se termine).

# A ADAPTER : même partage que Log-Connexion.ps1
$Partage = "\\SERVEUR\LogsConnexions$"

$Poste       = $env:COMPUTERNAME
$Fichier     = Join-Path $Partage "$Poste.csv"
$Utilisateur = "$env:USERDOMAIN\$env:USERNAME"
$Heure       = (Get-Date).ToString("HH:mm:ss")

if (-not (Test-Path -LiteralPath $Fichier)) { exit }

$utf8Bom = New-Object System.Text.UTF8Encoding($true)

# Quelques tentatives au cas où le fichier serait momentanément verrouillé
for ($essai = 0; $essai -lt 10; $essai++) {
    try {
        $lignes = [System.IO.File]::ReadAllLines($Fichier)

        # On cherche à partir de la fin la dernière ligne de cet utilisateur sans heure de déconnexion
        $index = -1
        for ($i = $lignes.Count - 1; $i -ge 1; $i--) {
            $champs = $lignes[$i].Split(';')
            if ($champs.Count -ge 2 -and $champs[1] -ieq $Utilisateur -and ($champs.Count -lt 5 -or [string]::IsNullOrEmpty($champs[4]))) {
                $index = $i
                break
            }
        }
        if ($index -lt 0) { break }   # rien à compléter

        $champs = $lignes[$index].Split(';')
        $lignes[$index] = ($champs[0..3] -join ';') + ';' + $Heure

        [System.IO.File]::WriteAllLines($Fichier, $lignes, $utf8Bom)
        break
    }
    catch {
        Start-Sleep -Milliseconds (Get-Random -Minimum 100 -Maximum 500)
    }
}
