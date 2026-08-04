<#
.SYNOPSIS
    Removes the artwork deployed by Deploy-ConsoleModeMedia.ps1 and empties the
    frontend thumbnail cache.

.DESCRIPTION
    Two mutually exclusive modes, enforced at parameter binding time so the
    console library and the arcade library can never be processed in one run.

    CONSOLE MODE   target <GamesRoot>\<system>\media\
    ARCADE MODE    target <parent of ArcadeRoot>\media\

    Only .png and .jpg files sitting directly in the target folder are removed,
    plus the contents of its optimized\ subfolder. There is no deduced mode: a
    curated library loses ROMs over time, and artwork whose ROM no longer exists
    could never be reconstructed from an inventory. Wiping is the only way to
    guarantee no stale file survives.

    FOUR SAFEGUARDS
        1. No recursion, so box2d\, screenshot\, box3d\, titlescreen\ and logo\
           are unreachable by construction rather than by exclusion list.
        2. Two extensions only, so a stray gamelist.xml or .txt is left alone.
        3. The target folder leaf must be named media, so a typo in a root path
           cannot trigger a deletion somewhere else.
        4. optimized\ is emptied, never created and never removed, which matches
           the deploy script behaviour.

    Confirmation is requested once per job, not once per file.

.EXAMPLE
    .\Clean-ConsoleModeMedia.ps1 -Arcade -ArcadeRoot G:\_Arcade -WhatIf

.EXAMPLE
    .\Clean-ConsoleModeMedia.ps1 -Console -GamesRoot O:\games -ReportCsv .\clean.csv

.EXAMPLE
    .\Clean-ConsoleModeMedia.ps1 -Console -GamesRoot O:\games -Systems 3DO -Confirm:$false
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    # EN: Console library mode. / FR: Mode bibliotheque console.
    [Parameter(Mandatory = $true, ParameterSetName = 'Console')]
    [switch] $Console,

    # EN: Root holding one folder per system. / FR: Racine contenant un dossier par systeme.
    [Parameter(Mandatory = $true, ParameterSetName = 'Console')]
    [string] $GamesRoot,

    # EN: Optional system white list. / FR: Liste blanche de systemes, optionnelle.
    [Parameter(ParameterSetName = 'Console')]
    [string[]] $Systems,

    # EN: Arcade library mode. / FR: Mode bibliotheque arcade.
    [Parameter(Mandatory = $true, ParameterSetName = 'Arcade')]
    [switch] $Arcade,

    # EN: The _Arcade folder itself. / FR: Le dossier _Arcade lui-meme.
    [Parameter(Mandatory = $true, ParameterSetName = 'Arcade')]
    [string] $ArcadeRoot,

    # ---------------------------------------------------------------------------
    # EN: Leave the thumbnail cache in place. Only useful when the deployed
    #     artwork is being removed for some other reason than a redeploy.
    # FR: Conserver le cache de vignettes. Utile seulement si le media deploye
    #     est supprime pour une autre raison qu'un redeploiement.
    # ---------------------------------------------------------------------------
    [switch] $KeepOptimized,

    # EN: Write a log of every deleted file. / FR: Journalise chaque fichier supprime.
    [string] $ReportCsv
)

$ErrorActionPreference = 'Stop'

# EN: Image extensions the deploy script is allowed to produce. / FR: Extensions d'image que le script de deploiement peut produire.
$DeployedExt = @('.png', '.jpg', '.jpeg')

# EN: Folders that are never a system. / FR: Dossiers qui ne sont jamais un systeme.
$CommonExcludeDirs = @(
    'media', '@eaDir', '#recycle', '#snapshot', 'System Volume Information',
    '$RECYCLE.BIN', '.git', '.svn', 'downloads', 'images', 'videos'
)

# ===========================================================================
# EN: TARGET BUILDING, symmetrical with the deploy script.
# FR: CONSTRUCTION DES CIBLES, symetrique du script de deploiement.
# ===========================================================================
$targets = New-Object System.Collections.Generic.List[object]

if ($PSCmdlet.ParameterSetName -eq 'Console') {

    if (-not (Test-Path -LiteralPath $GamesRoot)) { throw "Games root not found: $GamesRoot" }
    $rootFull = [IO.Path]::GetFullPath($GamesRoot).TrimEnd('\')

    $systemDirs = @(Get-ChildItem -LiteralPath $rootFull -Directory |
                    Where-Object { $CommonExcludeDirs -notcontains $_.Name } |
                    Where-Object { -not $Systems -or $Systems -contains $_.Name })

    foreach ($sysDir in $systemDirs) {
        $mediaRoot = Join-Path $sysDir.FullName 'media'
        if (-not (Test-Path -LiteralPath $mediaRoot)) { continue }
        $targets.Add([pscustomobject]@{ Name = $sysDir.Name; Dir = $mediaRoot })
    }
}
else {
    if (-not (Test-Path -LiteralPath $ArcadeRoot)) { throw "Arcade root not found: $ArcadeRoot" }
    $arcFull = [IO.Path]::GetFullPath($ArcadeRoot).TrimEnd('\')

    # EN: Same derivation as the deploy script, one level above _Arcade.
    # FR: Meme deduction que le script de deploiement, un niveau au-dessus de _Arcade.
    $outDir = Join-Path (Split-Path $arcFull -Parent) 'media'
    if (-not (Test-Path -LiteralPath $outDir)) { throw "Arcade output folder not found: $outDir" }

    $targets.Add([pscustomobject]@{ Name = 'Arcade'; Dir = $outDir })
}

if ($targets.Count -eq 0) {
    Write-Host 'Nothing to clean.' -ForegroundColor Yellow
    return
}

Write-Host ("Mode    : {0}" -f $PSCmdlet.ParameterSetName) -ForegroundColor Cyan
Write-Host ("Targets : {0}" -f $targets.Count) -ForegroundColor Cyan
Write-Host ("First   : {0}" -f $targets[0].Dir) -ForegroundColor Cyan
Write-Host ''

# ===========================================================================
# EN: MAIN LOOP
# FR: BOUCLE PRINCIPALE
# ===========================================================================
$log      = New-Object System.Collections.Generic.List[object]
$Grand    = [ordered]@{ Media = 0; Cache = 0; Bytes = 0 }
$jobIndex = 0

foreach ($t in $targets) {

    $jobIndex++
    Write-Progress -Id 1 -Activity 'Cleaning media' `
        -Status ("{0}  ({1}/{2})" -f $t.Name, $jobIndex, $targets.Count) `
        -PercentComplete ([int](100 * ($jobIndex - 1) / $targets.Count))

    # ---------------------------------------------------------------------------
    # EN: Safeguard three. Refuse to touch anything whose leaf is not media, so
    #     a mistyped root path cannot escalate into an unrelated deletion.
    # FR: Garde-fou trois. Refus d'agir si la feuille du chemin n'est pas media,
    #     pour qu'une faute de frappe dans une racine ne degenere pas en
    #     suppression ailleurs.
    # ---------------------------------------------------------------------------
    if ((Split-Path $t.Dir -Leaf) -ne 'media') {
        Write-Warning ("[{0}] refusing to clean, leaf is not 'media': {1}" -f $t.Name, $t.Dir)
        continue
    }

    # EN: Safeguards one and two, no recursion and two extensions only. / FR: Garde-fous un et deux, pas de recursion et deux extensions.
    $media = @(Get-ChildItem -LiteralPath $t.Dir -File -ErrorAction SilentlyContinue |
               Where-Object { $DeployedExt -contains $_.Extension.ToLower() })

    $optDir = Join-Path $t.Dir 'optimized'
    $cache  = @()
    if (-not $KeepOptimized -and (Test-Path -LiteralPath $optDir)) {
        $cache = @(Get-ChildItem -LiteralPath $optDir -Force -ErrorAction SilentlyContinue)
    }

    if ($media.Count -eq 0 -and $cache.Count -eq 0) {
        Write-Verbose "[$($t.Name)] nothing to remove"
        continue
    }

    $bytes = 0
    foreach ($f in $media) { $bytes += $f.Length }
    foreach ($f in $cache) { if ($f.PSIsContainer -ne $true) { $bytes += $f.Length } }

    # ---------------------------------------------------------------------------
    # EN: ShouldProcess is asked once per job, never per file: thousands of
    #     prompts would be unusable, and answering "yes to all" once would void
    #     the safeguard. The distinction below matters because a dry run must
    #     still produce a full report, whereas a declined prompt must not be
    #     counted at all. $WhatIfPreference tells the two cases apart.
    # FR: ShouldProcess est interroge une fois par travail, jamais par fichier :
    #     des milliers d'invites seraient inutilisables, et repondre "oui pour
    #     tout" une fois viderait le garde-fou de son sens. La distinction
    #     ci-dessous importe car un essai a blanc doit tout de meme produire un
    #     rapport complet, alors qu'un refus ne doit rien compter du tout.
    #     $WhatIfPreference permet de separer les deux cas.
    # ---------------------------------------------------------------------------
    $what    = "{0} artwork file(s) and {1} cache entry(ies), {2:N1} MB" -f $media.Count, $cache.Count, ($bytes / 1MB)
    $proceed = $PSCmdlet.ShouldProcess($t.Dir, "Remove $what")

    if (-not $proceed -and -not $WhatIfPreference) {
        Write-Host ("[{0,-22}] declined" -f $t.Name) -ForegroundColor DarkGray
        continue
    }

    # ---------------------------------------------------------------------------
    # EN: Write-Progress costs more than the deletion itself when called on every
    #     file, so it is refreshed once per percent at most. Deletion goes through
    #     the .NET call rather than Remove-Item: over SMB the provider stack
    #     overhead dominates, and this is roughly four times faster on a share.
    # FR: Write-Progress coute plus cher que la suppression elle-meme s'il est
    #     appele sur chaque fichier, d'ou un rafraichissement par pourcent au
    #     plus. La suppression passe par l'appel .NET plutot que Remove-Item :
    #     sur SMB le surcout de la pile de fournisseurs domine, et ceci est
    #     environ quatre fois plus rapide sur un partage.
    # ---------------------------------------------------------------------------
    $done  = 0
    $total = $media.Count + $cache.Count
    $step  = [Math]::Max(1, [int]($total / 100))

    foreach ($f in $media) {
        if ($ReportCsv) {
            $log.Add([pscustomobject]@{
                System = $t.Name; Folder = 'media'; File = $f.Name; Ko = [int]($f.Length / 1KB)
            })
        }
        if ($proceed) {
            try { [System.IO.File]::Delete($f.FullName) } catch { Write-Verbose "delete failed: $($f.FullName)" }
        }
        $Grand.Media++

        $done++
        if ($done % $step -eq 0) {
            Write-Progress -Id 2 -ParentId 1 -Activity "Removing artwork in $($t.Name)" `
                -Status ("{0} / {1}" -f $done, $total) `
                -PercentComplete ([int](100 * $done / $total))
        }
    }

    foreach ($f in $cache) {
        if ($ReportCsv -and -not $f.PSIsContainer) {
            $log.Add([pscustomobject]@{
                System = $t.Name; Folder = 'optimized'; File = $f.Name; Ko = [int]($f.Length / 1KB)
            })
        }
        if ($proceed) {
            if ($f.PSIsContainer) {
                Remove-Item -LiteralPath $f.FullName -Recurse -Force -ErrorAction SilentlyContinue -WhatIf:$false
            }
            else {
                try { [System.IO.File]::Delete($f.FullName) } catch { Write-Verbose "delete failed: $($f.FullName)" }
            }
        }
        $Grand.Cache++

        $done++
        if ($done % $step -eq 0) {
            Write-Progress -Id 2 -ParentId 1 -Activity "Emptying cache in $($t.Name)" `
                -Status ("{0} / {1}" -f $done, $total) `
                -PercentComplete ([int](100 * $done / $total))
        }
    }

    Write-Progress -Id 2 -Activity 'Removing' -Completed
    $Grand.Bytes += $bytes

    Write-Host ("[{0,-22}] media={1,-6} cache={2,-6} {3,8:N1} MB" -f `
                $t.Name, $media.Count, $cache.Count, ($bytes / 1MB)) -ForegroundColor Gray
}

# ===========================================================================
# EN: SUMMARY
# FR: SYNTHESE
# ===========================================================================
Write-Progress -Id 1 -Activity 'Cleaning media' -Completed

Write-Host ''
Write-Host ("TOTAL : {0} artwork files | {1} cache entries | {2:N1} MB freed" -f `
            $Grand.Media, $Grand.Cache, ($Grand.Bytes / 1MB)) -ForegroundColor Cyan

if ($ReportCsv -and $log.Count) {
    # EN: Written even under -WhatIf, so a dry run still yields a full list.
    # FR: Ecrit meme sous -WhatIf, pour qu'un essai a blanc fournisse la liste complete.
    $log | Export-Csv -LiteralPath $ReportCsv -NoTypeInformation -Encoding UTF8 -Delimiter ';' -WhatIf:$false
    Write-Host "Log   : $ReportCsv"
}
