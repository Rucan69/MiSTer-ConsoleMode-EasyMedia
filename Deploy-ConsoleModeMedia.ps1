<#
.SYNOPSIS
    Deploys already-scraped artwork into the media folder read by the console
    mode frontend, renaming each file after the exact ROM name.

.DESCRIPTION
    Two mutually exclusive modes, enforced at parameter binding time so the
    console library and the arcade library can never be processed in one run.

    CONSOLE MODE
        ROMs      <GamesRoot>\<system>\             recursive
        Sources   <GamesRoot>\<system>\media\box2d\
                  <GamesRoot>\<system>\media\screenshot\
        Gamelist  <GamesRoot>\<system>\gamelist.xml recursive lookup
        Output    <GamesRoot>\<system>\media\

    ARCADE MODE
        ROMs      <ArcadeRoot>\*.mra                recursive, _Organized skipped
        Sources   <ArcadeRoot>\media\box2d\
                  <ArcadeRoot>\media\screenshot\
        Gamelist  <ArcadeRoot>\gamelist.xml
        Output    <parent of ArcadeRoot>\media\

    Target names are the ROM base name plus the extension of the source image,
    so a JPEG source stays JPEG. A previously deployed twin carrying the other
    extension is removed before writing.

    The box2d\ and screenshot\ source folders and every gamelist.xml are never
    modified. Physical copies only, no links.

    RESOLUTION CHAIN
        1. gamelist  explicit path to media mapping, with parentid inheritance
        2. manual    hard-coded exception table, see $ManualMap
        3. glname    lookup by the name declared in the gamelist
        4. folder    inheritance from a parent folder entry
        5. norm      normalised ROM file name
        6. noplus    same with plus signs dropped instead of spelled out
        7. prefix    ROM key is a unique prefix of a media key
        8. rprefix   a media key is a unique prefix of the ROM key
        9. fuzzy     normalised without articles

.EXAMPLE
    .\Deploy-ConsoleModeMedia.ps1 -Arcade -ArcadeRoot G:\_Arcade -WhatIf

.EXAMPLE
    .\Deploy-ConsoleModeMedia.ps1 -Console -GamesRoot O:\games -ReportCsv .\console.csv

.EXAMPLE
    .\Deploy-ConsoleModeMedia.ps1 -Console -GamesRoot O:\games -Systems psx,snes -NoOverwrite
#>

[CmdletBinding(SupportsShouldProcess = $true)]
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

    # EN: Which box artwork variant to pull. / FR: Variante de jaquette a utiliser.
    [ValidateSet('box2d', 'box3d')]
    [string] $BoxDir = 'box2d',

    # EN: Which snapshot variant to pull. / FR: Variante de capture a utiliser.
    [ValidateSet('screenshot', 'titlescreen')]
    [string] $ScreenDir = 'screenshot',

    # ---------------------------------------------------------------------------
    # EN: Incremental mode. Existing targets are left alone and the optimized
    #     cache is preserved, because nothing already deployed was replaced.
    # FR: Mode incrementiel. Les cibles existantes sont conservees et le cache
    #     optimized n'est pas vide, puisque rien de deja deploye n'a change.
    # ---------------------------------------------------------------------------
    [switch] $NoOverwrite,

    # EN: Write a per-ROM report plus an orphan media list. / FR: Rapport par ROM et liste des medias orphelins.
    [string] $ReportCsv
)

$ErrorActionPreference = 'Stop'

# ===========================================================================
# EN: MANUAL EXCEPTION TABLE
#     Key   : "<SystemName>|<normalised ROM key>"
#     Value : media file name without extension, exactly as stored on disk.
#             The same name is looked up in the box and snapshot folders.
#     These cases are unreachable by heuristic: the ROM title is a suffix, an
#     infix, or shares no word at all with the media title.
# FR: TABLE D'EXCEPTIONS MANUELLES
#     Cle    : "<NomDuSysteme>|<cle normalisee de la ROM>"
#     Valeur : nom du fichier media sans extension, tel qu'il est sur le disque.
#              Le meme nom est cherche dans les deux dossiers source.
#     Ces cas sont hors de portee des heuristiques : le titre de la ROM est un
#     suffixe, un infixe, ou ne partage aucun mot avec celui du media.
# ===========================================================================
$ManualMap = @{
    # EN: Neo Geo, alternate JP and US titles. / FR: Neo Geo, titres alternatifs JP et US.
    'NEOGEO|kabukiklash'          = 'Far East of Eden- Kabuki Klash'
    'NEOGEO|masterofshougi'       = 'Syougi No Tatsujin - Master of Syougi'
    'NEOGEO|quizdaisousasenpart2' = 'Quiz Meitantei Neo&Geo - Quiz Daisousa Sen part 2'
    'NEOGEO|supersidekicks4'      = 'The Ultimate 11- SNK Football Championship'

    # EN: Astrocade, games listed in a different order on the cartridge.
    # FR: Astrocade, jeux enumeres dans un autre ordre sur la cartouche.
    'Astrocade|blackjackaceydeuceypoker' = 'Blackjack+poker+acey-deucy'

    # EN: VC4000, abbreviated file name, media filed under the cassette number.
    # FR: VC4000, nom de fichier abrege, media range sous le numero de cassette.
    'VC4000|superinv' = 'Cassette 33 - Super Invaders'

    # EN: Game Boy Color. / FR: Game Boy Color.
    'GBC|sesamestreettheadventuresofelmoingrouchland' = 'The Adventures of Elmo in Grouchland'

    # ---------------------------------------------------------------------------
    # EN: NEEDS CHECKING. Shelly Club in Europe and Kelly Club in the US are
    #     probably the same game, but this was never confirmed. Comment the line
    #     out if the artwork looks wrong in the frontend.
    # FR: A VERIFIER. Shelly Club en Europe et Kelly Club aux Etats-Unis sont
    #     probablement le meme jeu, sans confirmation. Commenter la ligne si la
    #     jaquette affichee est incoherente.
    # ---------------------------------------------------------------------------
    'GBC|shellyclub' = 'Kelly Club - Clubhouse Fun'
}

# ===========================================================================
# EN: EXTENSION AND FOLDER RULES, hard-coded per mode.
# FR: REGLES D'EXTENSIONS ET DE DOSSIERS, figees selon le mode.
# ===========================================================================

# EN: Never a ROM: artwork, metadata, saves, MiSTer support files, BIOS blobs.
# FR: Jamais une ROM : media, metadonnees, saves, fichiers de support MiSTer, BIOS.
$IgnoreExt = @(
    '.png', '.jpg', '.jpeg', '.bmp', '.gif', '.webp', '.mp4', '.avi', '.mkv', '.pdf',
    '.xml', '.txt', '.dat', '.nfo', '.db', '.ini', '.cfg', '.json', '.csv', '.log', '.sqlite',
    '.url', '.lnk', '.md5', '.sha1', '.torrent',
    '.sav', '.srm', '.state', '.ips', '.bps',
    # ---------------------------------------------------------------------------
    # EN: MiSTer support files. Palettes, borders and overlays sit next to the
    #     ROMs and would otherwise be counted as games. .sgb holds Super Game Boy
    #     borders, several per title, named after the game: without this line the
    #     heuristic levels happily hand them the artwork of the real ROM.
    #     Note that a genuine Super Game Boy cartridge is an SNES .sfc file, so
    #     nothing playable is lost here.
    # FR: Fichiers de support MiSTer. Palettes, bordures et overlays cohabitent
    #     avec les ROMs et seraient sinon comptes comme des jeux. Le .sgb contient
    #     les bordures Super Game Boy, plusieurs par titre, nommees d'apres le
    #     jeu : sans cette ligne les niveaux heuristiques leur attribuent
    #     volontiers la jaquette de la vraie ROM. A noter qu'une cartouche Super
    #     Game Boy authentique est un fichier SNES .sfc, donc rien de jouable
    #     n'est perdu ici.
    # ---------------------------------------------------------------------------
    '.pal', '.gbp', '.bor', '.ovr', '.sgb', '.jce', '.jmc',
    '.sfix', '.sp1', '.lo', '.drv', '.inf', '.exe'
)

# EN: Companion tracks, never launchable on their own. / FR: Pistes annexes, jamais lancables seules.
$CompanionExt = @('.sub', '.ccd', '.raw', '.wav', '.ogg', '.mp3', '.flac', '.aiff')

# ---------------------------------------------------------------------------
# EN: A .bin or .img is a CD track only when a CD index file sits in the same
#     folder. Otherwise it is a genuine ROM, which is the case for Odyssey2,
#     Channel F, Arcadia, VC4000, Astrocade, CreatiVision, MyVision and the
#     Atari 7800.
# FR: Un .bin ou .img n'est une piste CD que si un fichier d'index CD se trouve
#     dans le meme dossier. Sinon c'est une vraie ROM, ce qui est le cas pour
#     Odyssey2, Channel F, Arcadia, VC4000, Astrocade, CreatiVision, MyVision
#     et l'Atari 7800.
# ---------------------------------------------------------------------------
$ConditionalCompanionExt = @('.bin', '.img')
$IndexExt                = @('.cue', '.gdi', '.toc', '.m3u')

# EN: BIOS and firmware blobs that would otherwise count as missing artwork.
# FR: BIOS et firmwares qui seraient sinon comptes comme jaquettes manquantes.
$BiosPatterns = @(
    'bios*', '*bios*.rom', 'boot*.rom', 'kanji.rom', '*.bios',
    'neogeo.zip', 'sbi.zip', 'top-sp1.bin', '.delme',
    'Super Game Boy*.sfc', 'mister-boot.*', 'mister-demo.*'
)

# EN: Extensions accepted as artwork inside a gamelist tag. / FR: Extensions acceptees comme media dans une balise gamelist.
$MediaFileExt = @('.png', '.jpg', '.jpeg', '.webp', '.bmp', '.gif', '.mp4', '.avi', '.pdf')

# EN: Folders skipped while walking a library. / FR: Dossiers ignores lors du parcours d'une bibliotheque.
$CommonExcludeDirs = @(
    'media', '@eaDir', '#recycle', '#snapshot', 'System Volume Information',
    '$RECYCLE.BIN', '.git', '.svn', 'downloads', 'images', 'videos'
)

# EN: Suffix appended to the snapshot copy. / FR: Suffixe ajoute a la copie de capture.
$BgSuffix = '-BG'

# ===========================================================================
# EN: NAME NORMALISATION
# FR: NORMALISATION DES NOMS
# ===========================================================================

# EN: Articles that regional naming conventions push to the end of a title.
# FR: Articles que les conventions de nommage regionales rejettent en fin de titre.
$ArticleAlt = "The|An|A|Los|Las|Les|Le|La|L'|El|Lo|Gli|Il|I|Der|Die|Das|Den|Dem|Ein|Eine|De|Het|Os|As|Um|Uma|O"
$RotateRx   = [regex]::new("^(.*?),\s+($ArticleAlt)((?:\s+-\s+|\s*:\s*).*)?$",
                           [Text.RegularExpressions.RegexOptions]::IgnoreCase)

function Get-NormKey {
    <#
        EN: Reduces a title to a comparison key. Region and version tags are
            stripped, a trailing article is rotated back to the front, then all
            punctuation and case are discarded.
        FR: Reduit un titre a une cle de comparaison. Les tags de region et de
            version sont supprimes, un article postpose est repivote en tete,
            puis toute la ponctuation et la casse sont abandonnees.
    #>
    param([string] $Name, [switch] $DropArticles, [switch] $DropPlus)

    $key = $Name

    # EN: Remove every parenthesised and bracketed group, repeatedly. / FR: Supprime tous les groupes parentheses et crochets, en boucle.
    while ($key -match '[\(\[][^\(\)\[\]]*[\)\]]') {
        $key = [regex]::Replace($key, '\s*[\(\[][^\(\)\[\]]*[\)\]]', '')
    }
    $key = $key.Trim()

    # EN: "Legend of Zelda, The - X" becomes "The Legend of Zelda - X".
    # FR: "Legend of Zelda, The - X" devient "The Legend of Zelda - X".
    $rot = $RotateRx.Match($key)
    if ($rot.Success) {
        $key = ('{0} {1}{2}' -f $rot.Groups[2].Value, $rot.Groups[1].Value, $rot.Groups[3].Value)
    }

    $key = $key.ToLowerInvariant()
    $key = $key -replace '&', ' and '

    # ---------------------------------------------------------------------------
    # EN: Two possible treatments of the plus sign. Spelled out by default,
    #     dropped for the alternate index, which reconciles "Red Baron, Panzer
    #     Attack" with "Red Baron + Panzer Attack" on Astrocade multi-game carts.
    # FR: Deux traitements possibles du signe plus. Traduit par defaut, supprime
    #     pour l'index alternatif, ce qui reconcilie "Red Baron, Panzer Attack"
    #     et "Red Baron + Panzer Attack" sur les cartouches multi-jeux Astrocade.
    # ---------------------------------------------------------------------------
    if ($DropPlus) { $key = $key -replace '\+', ' ' }
    else           { $key = $key -replace '\+', ' plus ' }

    if ($DropArticles) {
        $key = $key -replace "\bl'", ' '
        $key = $key -replace "\b(the|an|a|le|la|les|l|el|los|las|il|lo|gli|der|die|das|den|ein|eine|de|het|o|os|um|uma)\b", ' '
    }

    # ---------------------------------------------------------------------------
    # EN: FormKD is the compatibility decomposition. Beyond accents it folds
    #     superscripts, so a title spelled with a superscript two and the same
    #     title spelled with a plain two produce one key.
    # FR: FormKD est la decomposition de compatibilite. Au-dela des accents elle
    #     replie les exposants, de sorte qu'un titre ecrit avec un deux en
    #     exposant et le meme avec un deux normal produisent une seule cle.
    # ---------------------------------------------------------------------------
    $key = $key.Normalize([Text.NormalizationForm]::FormKD)
    $key = ($key.ToCharArray() | Where-Object {
              [Globalization.CharUnicodeInfo]::GetUnicodeCategory($_) -ne 'NonSpacingMark'
            }) -join ''
    $key = $key -replace '[^a-z0-9]', ''
    return $key
}

function New-CIDict {
    # EN: Case insensitive dictionary, needed because ext4 is case sensitive.
    # FR: Dictionnaire insensible a la casse, necessaire car ext4 y est sensible.
    New-Object 'System.Collections.Generic.Dictionary[string,string]' ([StringComparer]::OrdinalIgnoreCase)
}

function Resolve-RelPath {
    # EN: Turns a gamelist relative path into an absolute one. / FR: Transforme un chemin relatif du gamelist en absolu.
    param([string] $Base, [string] $Rel)

    if ([string]::IsNullOrWhiteSpace($Rel)) { return $null }
    $r = $Rel.Trim().Replace('/', '\')
    if ($r.StartsWith('.\')) { $r = $r.Substring(2) }
    $r = $r.TrimStart('\')
    if ([IO.Path]::IsPathRooted($r)) { return [IO.Path]::GetFullPath($r) }
    try { return [IO.Path]::GetFullPath((Join-Path $Base $r)) } catch { return $null }
}

function Get-NodeMedia {
    <#
        EN: Extracts artwork paths from an XML node without assuming tag names.
            Any child element whose text points inside a media folder and ends
            with an image extension is considered, then classified by the folder
            it actually lives in. This survives boxart2d, image, thumbnail and
            whatever the scraper invents next.
        FR: Extrait les chemins de media d'un noeud XML sans presumer du nom des
            balises. Toute balise fille dont le texte pointe dans un dossier
            media et se termine par une extension d'image est retenue, puis
            classee d'apres le dossier ou elle reside reellement. Cela encaisse
            boxart2d, image, thumbnail et ce que le scraper inventera ensuite.
    #>
    param($Node, [string] $ListDir, [string] $BoxLeaf, [string] $ScreenLeaf)

    $out = @{}
    foreach ($child in $Node.ChildNodes) {
        if ($child.NodeType -ne [System.Xml.XmlNodeType]::Element) { continue }
        $txt = $child.InnerText
        if ([string]::IsNullOrWhiteSpace($txt)) { continue }
        if ($txt -notmatch '[\\/]media[\\/]') { continue }
        if ($MediaFileExt -notcontains ([IO.Path]::GetExtension($txt).ToLower())) { continue }

        $mPath = Resolve-RelPath $ListDir $txt
        if (-not $mPath -or -not (Test-Path -LiteralPath $mPath)) { continue }

        $leaf = Split-Path (Split-Path $mPath -Parent) -Leaf
        if     ($leaf -eq $BoxLeaf    -and -not $out.ContainsKey('Box'))  { $out['Box']  = $mPath }
        elseif ($leaf -eq $ScreenLeaf -and -not $out.ContainsKey('Shot')) { $out['Shot'] = $mPath }
    }
    return $out
}

function Read-Gamelist {
    <#
        EN: Parses one or more gamelist.xml files. Two layouts are supported.
            Classic EmulationStation puts the path and the artwork tags in the
            same game element. ZaparooCompanion splits them: a canonical entry
            with an id attribute carries the name and the artwork, while child
            entries with a parentid attribute carry only the ROM path. The join
            is resolved here, which is what makes arcade work at all since three
            quarters of MRA names differ from their artwork name.
        FR: Analyse un ou plusieurs gamelist.xml. Deux structures sont gerees.
            EmulationStation classique place le chemin et les balises media dans
            le meme element game. ZaparooCompanion les separe : une entree
            canonique portant un attribut id contient le nom et les medias,
            tandis que les entrees filles a attribut parentid ne portent que le
            chemin de la ROM. La jointure est resolue ici, ce qui est
            indispensable a l'arcade puisque trois quarts des noms de MRA
            different de leur media.
    #>
    param([string[]] $ListPaths, [string] $BoxLeaf, [string] $ScreenLeaf)

    $result = [pscustomobject]@{
        GameBox    = New-CIDict
        GameShot   = New-CIDict
        GameName   = New-CIDict
        FolderBox  = New-CIDict
        FolderShot = New-CIDict
        Files      = 0
        Entries    = 0
        Inherited  = 0
        Errors     = New-Object System.Collections.Generic.List[string]
    }

    foreach ($listPath in $ListPaths) {

        # ---------------------------------------------------------------------------
        # EN: Generated gamelists regularly contain control characters or badly
        #     escaped ampersands inside descriptions, so character checking is
        #     disabled rather than losing a whole system over one bad byte.
        # FR: Les gamelists generes contiennent regulierement des caracteres de
        #     controle ou des esperluettes mal echappees dans les descriptions,
        #     d'ou la desactivation du controle de caracteres plutot que de
        #     perdre tout un systeme pour un octet fautif.
        # ---------------------------------------------------------------------------
        $settings = New-Object System.Xml.XmlReaderSettings
        $settings.CheckCharacters  = $false
        $settings.DtdProcessing    = 'Ignore'
        $settings.IgnoreComments   = $true
        $settings.IgnoreWhitespace = $true

        $doc = New-Object System.Xml.XmlDocument
        try {
            $reader = [System.Xml.XmlReader]::Create($listPath, $settings)
            try { $doc.Load($reader) } finally { $reader.Close() }
        } catch {
            $result.Errors.Add("$listPath : $($_.Exception.Message)")
            continue
        }
        $result.Files++
        $listDir = Split-Path $listPath -Parent

        # EN: Pass one, index every canonical entry by its id. / FR: Passe 1, indexer les entrees canoniques par id.
        $byId        = @{}
        $parentCache = @{}
        foreach ($n in $doc.SelectNodes('//game | //folder')) {
            $idAttr = $n.GetAttribute('id')
            if ($idAttr) { $byId[$idAttr] = $n }
        }

        # EN: Pass two, process every entry carrying a path. / FR: Passe 2, traiter les entrees porteuses d'un chemin.
        foreach ($node in $doc.SelectNodes('//game | //folder')) {

            $pathNode = $node.SelectSingleNode('path')
            if (-not $pathNode -or [string]::IsNullOrWhiteSpace($pathNode.InnerText)) { continue }
            $target = Resolve-RelPath $listDir $pathNode.InnerText
            if (-not $target) { continue }

            $result.Entries++
            $isFolder = ($node.LocalName -eq 'folder')

            $media    = Get-NodeMedia -Node $node -ListDir $listDir -BoxLeaf $BoxLeaf -ScreenLeaf $ScreenLeaf
            $nameNode = $node.SelectSingleNode('name')
            $nameTxt  = if ($nameNode) { $nameNode.InnerText.Trim() } else { '' }

            # EN: Inherit artwork and title from the canonical entry. / FR: Herite media et titre de l'entree canonique.
            $parentId = $node.GetAttribute('parentid')
            if ($parentId -and $byId.ContainsKey($parentId)) {
                $parent = $byId[$parentId]

                if (-not $parentCache.ContainsKey($parentId)) {
                    $parentCache[$parentId] = Get-NodeMedia -Node $parent -ListDir $listDir -BoxLeaf $BoxLeaf -ScreenLeaf $ScreenLeaf
                }
                $pm = $parentCache[$parentId]

                $gained = $false
                if (-not $media.ContainsKey('Box')  -and $pm.ContainsKey('Box'))  { $media['Box']  = $pm['Box'];  $gained = $true }
                if (-not $media.ContainsKey('Shot') -and $pm.ContainsKey('Shot')) { $media['Shot'] = $pm['Shot']; $gained = $true }
                if ($gained) { $result.Inherited++ }

                if (-not $nameTxt) {
                    $pn = $parent.SelectSingleNode('name')
                    if ($pn) { $nameTxt = $pn.InnerText.Trim() }
                }
            }

            if ($nameTxt -and -not $isFolder) { $result.GameName[$target] = $nameTxt }

            if ($media.ContainsKey('Box')) {
                if ($isFolder) { if (-not $result.FolderBox.ContainsKey($target))  { $result.FolderBox[$target]  = $media['Box'] } }
                else           { if (-not $result.GameBox.ContainsKey($target))    { $result.GameBox[$target]    = $media['Box'] } }
            }
            if ($media.ContainsKey('Shot')) {
                if ($isFolder) { if (-not $result.FolderShot.ContainsKey($target)) { $result.FolderShot[$target] = $media['Shot'] } }
                else           { if (-not $result.GameShot.ContainsKey($target))   { $result.GameShot[$target]   = $media['Shot'] } }
            }
        }
    }

    return $result
}

function New-MediaIndex {
    <#
        EN: Indexes a source artwork folder by normalised name. Three tables are
            built: the primary key, a variant with plus signs dropped, and a
            variant with articles removed, each feeding its own resolution level.
        FR: Indexe un dossier de media source par nom normalise. Trois tables
            sont construites : la cle primaire, une variante sans signe plus et
            une variante sans articles, chacune alimentant son niveau de
            resolution.
    #>
    param([string] $Path)

    $primary    = @{}
    $plusless   = @{}
    $loose      = @{}
    $collisions = New-Object System.Collections.Generic.List[string]
    $used       = @{}

    if (-not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]@{
            Primary = $primary; NoPlus = $plusless; Loose = $loose; Keys = @()
            Collisions = $collisions; Used = $used; Count = 0; Path = $Path
        }
    }

    $files = @(Get-ChildItem -LiteralPath $Path -File -ErrorAction SilentlyContinue)
    foreach ($file in $files) {
        $base = [IO.Path]::GetFileNameWithoutExtension($file.Name)

        $k1 = Get-NormKey $base
        if ($k1) {
            if ($primary.ContainsKey($k1)) {
                $collisions.Add(("{0}  <=>  {1}" -f $file.Name, [IO.Path]::GetFileName($primary[$k1])))
            } else {
                $primary[$k1] = $file.FullName
            }
        }

        $kp = Get-NormKey $base -DropPlus
        if ($kp -and -not $plusless.ContainsKey($kp)) { $plusless[$kp] = $file.FullName }

        $k2 = Get-NormKey $base -DropArticles
        if ($k2 -and -not $loose.ContainsKey($k2)) { $loose[$k2] = $file.FullName }
    }

    [pscustomobject]@{
        Primary = $primary; NoPlus = $plusless; Loose = $loose; Keys = @($primary.Keys)
        Collisions = $collisions; Used = $used; Count = $files.Count; Path = $Path
    }
}

function Find-PrefixMatch {
    <#
        EN: The ROM key is a strict prefix of exactly one media key. Covers
            subtitles absent from the ROM name, as in "Art of Fighting 3" against
            "Art of Fighting 3 - The Path of the Warrior". Uniqueness is
            mandatory so that "Metal Slug" cannot swallow "Metal Slug X".
        FR: La cle ROM est un prefixe strict d'exactement une cle media. Couvre
            les sous-titres absents du nom de ROM, comme "Art of Fighting 3" face
            a "Art of Fighting 3 - The Path of the Warrior". L'unicite est
            obligatoire pour que "Metal Slug" ne capture pas "Metal Slug X".
    #>
    param($Idx, [string] $Key, [int] $MinLen = 8)

    if (-not $Key -or $Key.Length -lt $MinLen) { return $null }
    $hits = @($Idx.Keys | Where-Object { $_.Length -gt $Key.Length -and $_.StartsWith($Key) })
    if ($hits.Count -eq 1) { return $Idx.Primary[$hits[0]] }
    return $null
}

function Find-ReversePrefixMatch {
    <#
        EN: The opposite case, a media key is a strict prefix of the ROM key, as
            in "Jeep Jamboree" against "Jeep Jamboree - Off-Road Adventure". The
            minimum length is raised because a short media name would otherwise
            prefix many unrelated ROMs.
        FR: Le cas inverse, une cle media est un prefixe strict de la cle ROM,
            comme "Jeep Jamboree" face a "Jeep Jamboree - Off-Road Adventure".
            La longueur minimale est relevee car un nom de media court
            prefixerait sinon de nombreuses ROMs sans rapport.
    #>
    param($Idx, [string] $Key, [int] $MinLen = 10)

    if (-not $Key -or $Key.Length -le $MinLen) { return $null }
    $hits = @($Idx.Keys | Where-Object {
        $_.Length -ge $MinLen -and $_.Length -lt $Key.Length -and $Key.StartsWith($_)
    })
    if ($hits.Count -eq 1) { return $Idx.Primary[$hits[0]] }
    return $null
}

function Resolve-Media {
    <#
        EN: Walks the nine resolution levels and returns the first hit, tagged
            with the level that produced it so the report stays auditable.
        FR: Parcourt les neuf niveaux de resolution et renvoie le premier
            resultat, etiquete du niveau qui l'a produit pour que le rapport
            reste auditable.
    #>
    param(
        [string] $RomPath,
        [string] $RomBase,
        [string] $RomDir,
        [string] $SystemName,
        $Gl,
        $Idx,
        [ValidateSet('Box', 'Shot')] [string] $Kind
    )

    # EN: 1. gamelist, the only source of truth. / FR: 1. gamelist, seule source de verite.
    if ($Gl) {
        $direct = if ($Kind -eq 'Box') { $Gl.GameBox } else { $Gl.GameShot }
        if ($direct.ContainsKey($RomPath)) {
            $hit = $direct[$RomPath]; $Idx.Used[$hit] = $true
            return [pscustomobject]@{ Path = $hit; Match = 'gamelist' }
        }
    }

    $k1 = Get-NormKey $RomBase

    # EN: 2. manual override. / FR: 2. surcharge manuelle.
    $mk = "$SystemName|$k1"
    if ($ManualMap.ContainsKey($mk)) {
        $wanted = Get-NormKey $ManualMap[$mk]
        if ($wanted -and $Idx.Primary.ContainsKey($wanted)) {
            $hit = $Idx.Primary[$wanted]; $Idx.Used[$hit] = $true
            return [pscustomobject]@{ Path = $hit; Match = 'manual' }
        }
    }

    # EN: 3. title declared in the gamelist. / FR: 3. titre declare au gamelist.
    $glKey = $null
    if ($Gl -and $Gl.GameName.ContainsKey($RomPath)) {
        $glKey = Get-NormKey $Gl.GameName[$RomPath]
        if ($glKey -and $Idx.Primary.ContainsKey($glKey)) {
            $hit = $Idx.Primary[$glKey]; $Idx.Used[$hit] = $true
            return [pscustomobject]@{ Path = $hit; Match = 'glname' }
        }
    }

    # EN: 4. inheritance from a parent folder entry. / FR: 4. heritage d'une entree de dossier parent.
    if ($Gl) {
        $fdir = if ($Kind -eq 'Box') { $Gl.FolderBox } else { $Gl.FolderShot }
        if ($fdir.ContainsKey($RomDir)) {
            $hit = $fdir[$RomDir]; $Idx.Used[$hit] = $true
            return [pscustomobject]@{ Path = $hit; Match = 'folder' }
        }
    }

    # EN: 5. plain normalisation. / FR: 5. normalisation simple.
    if ($k1 -and $Idx.Primary.ContainsKey($k1)) {
        $hit = $Idx.Primary[$k1]; $Idx.Used[$hit] = $true
        return [pscustomobject]@{ Path = $hit; Match = 'norm' }
    }

    # EN: 6. alternate key with plus signs dropped. / FR: 6. cle alternative sans signe plus.
    $kp = Get-NormKey $RomBase -DropPlus
    if ($kp -and $Idx.NoPlus.ContainsKey($kp)) {
        $hit = $Idx.NoPlus[$kp]; $Idx.Used[$hit] = $true
        return [pscustomobject]@{ Path = $hit; Match = 'noplus' }
    }

    # EN: 7 and 8. prefix, then reverse prefix. / FR: 7 et 8. prefixe, puis prefixe inverse.
    foreach ($cand in @($glKey, $k1)) {
        $hit = Find-PrefixMatch -Idx $Idx -Key $cand
        if ($hit) { $Idx.Used[$hit] = $true; return [pscustomobject]@{ Path = $hit; Match = 'prefix' } }
    }
    foreach ($cand in @($k1, $glKey)) {
        $hit = Find-ReversePrefixMatch -Idx $Idx -Key $cand
        if ($hit) { $Idx.Used[$hit] = $true; return [pscustomobject]@{ Path = $hit; Match = 'rprefix' } }
    }

    # EN: 9. last resort, articles removed. / FR: 9. dernier recours, articles supprimes.
    $k2 = Get-NormKey $RomBase -DropArticles
    if ($k2 -and $Idx.Loose.ContainsKey($k2)) {
        $hit = $Idx.Loose[$k2]; $Idx.Used[$hit] = $true
        return [pscustomobject]@{ Path = $hit; Match = 'fuzzy' }
    }

    return $null
}

function Get-TwinNames {
    # EN: Sibling file names carrying the other image extensions. / FR: Noms de fichiers freres portant les autres extensions d'image.
    param([string] $Base, [string] $KeepExt)

    $out = @()
    foreach ($e in @('.png', '.jpg', '.jpeg')) {
        if ($e -eq $KeepExt.ToLower()) { continue }
        $out += "$Base$e"
    }
    return $out
}

function Copy-Media {
    <#
        EN: Copies one artwork file, keeping the source extension. The twin
            carrying the other extension is removed first, otherwise a source
            that switched from PNG to JPEG between two scrapes would leave two
            competing files and the frontend would pick the stale one.

            Existence is tested against an in-memory index of the output folder
            rather than with Test-Path, and the copy goes through the .NET call
            rather than Copy-Item. On a network share this matters enormously:
            a full console run would otherwise fire around forty thousand
            provider round trips just to look for twins.
        FR: Copie un fichier media en conservant l'extension source. Le jumeau
            portant l'autre extension est supprime au prealable, sinon une source
            passee de PNG a JPEG entre deux scraps laisserait deux fichiers
            concurrents et le frontend choisirait le perime.

            L'existence est testee contre un index en memoire du dossier de
            sortie plutot qu'avec Test-Path, et la copie passe par l'appel .NET
            plutot que Copy-Item. Sur un partage reseau la difference est
            enorme : un run console complet declencherait sinon environ quarante
            mille allers-retours de fournisseur juste pour chercher des jumeaux.
    #>
    param(
        [string] $Source,
        [string] $TargetDir,
        [string] $TargetName,
        [string[]] $TwinNames,
        $Existing
    )

    $target = Join-Path $TargetDir $TargetName

    if ($NoOverwrite) {
        # EN: Any existing variant means this game is already covered. / FR: Toute variante existante signifie ce jeu deja couvert.
        if ($Existing.Contains($TargetName)) { return 'skipped' }
        foreach ($n in $TwinNames) { if ($Existing.Contains($n)) { return 'skipped' } }
    }
    else {
        foreach ($n in $TwinNames) {
            if (-not $Existing.Contains($n)) { continue }
            $twin = Join-Path $TargetDir $n
            if ($PSCmdlet.ShouldProcess($twin, 'Remove stale twin')) {
                try { [System.IO.File]::Delete($twin) } catch { Write-Verbose "delete failed: $twin" }
            }
            $Existing.Remove($n) | Out-Null
        }
    }

    if ($PSCmdlet.ShouldProcess($target, "Copy from $([IO.Path]::GetFileName($Source))")) {
        try { [System.IO.File]::Copy($Source, $target, $true) }
        catch { Write-Warning "copy failed: $target -> $($_.Exception.Message)" ; return 'skipped' }
    }
    $Existing.Add($TargetName) | Out-Null
    return 'copied'
}

# ===========================================================================
# EN: JOB BUILDING. One job per system in console mode, a single job in arcade
#     mode. A job carries every path and rule the main loop needs, which is what
#     keeps the two libraries from ever sharing state.
# FR: CONSTRUCTION DES TRAVAUX. Un travail par systeme en mode console, un seul
#     en mode arcade. Un travail porte tous les chemins et regles dont la boucle
#     principale a besoin, ce qui empeche les deux bibliotheques de partager
#     quoi que ce soit.
# ===========================================================================
$jobs = New-Object System.Collections.Generic.List[object]

if ($PSCmdlet.ParameterSetName -eq 'Console') {

    if (-not (Test-Path -LiteralPath $GamesRoot)) { throw "Games root not found: $GamesRoot" }
    $rootFull = [IO.Path]::GetFullPath($GamesRoot).TrimEnd('\')

    $systemDirs = @(Get-ChildItem -LiteralPath $rootFull -Directory |
                    Where-Object { $CommonExcludeDirs -notcontains $_.Name } |
                    Where-Object { -not $Systems -or $Systems -contains $_.Name })

    foreach ($sysDir in $systemDirs) {

        $mediaRoot = Join-Path $sysDir.FullName 'media'
        if (-not (Test-Path -LiteralPath $mediaRoot)) {
            Write-Verbose "[$($sysDir.Name)] no media folder, skipped"
            continue
        }

        # EN: Recursive lookup, PSX keeps multi-disc sets in subfolders. / FR: Recherche recursive, la PSX range ses multi-disques en sous-dossiers.
        $lists    = @()
        $rootList = Join-Path $sysDir.FullName 'gamelist.xml'
        if (Test-Path -LiteralPath $rootList) { $lists += $rootList }
        $lists += @(Get-ChildItem -LiteralPath $sysDir.FullName -Filter 'gamelist.xml' -Recurse -File -ErrorAction SilentlyContinue |
                    Where-Object { $_.FullName -ne $rootList } |
                    Select-Object -ExpandProperty FullName)

        $jobs.Add([pscustomobject]@{
            Name         = $sysDir.Name
            RomRoot      = $sysDir.FullName
            MediaRoot    = $mediaRoot
            OutDir       = $mediaRoot
            Gamelists    = $lists
            OnlyExt      = $null
            ExcludeDirs  = $CommonExcludeDirs
            ExcludeFiles = $BiosPatterns
        })
    }
}
else {
    if (-not (Test-Path -LiteralPath $ArcadeRoot)) { throw "Arcade root not found: $ArcadeRoot" }
    $arcFull = [IO.Path]::GetFullPath($ArcadeRoot).TrimEnd('\')

    $mediaRoot = Join-Path $arcFull 'media'
    if (-not (Test-Path -LiteralPath $mediaRoot)) { throw "Arcade media folder not found: $mediaRoot" }

    # ---------------------------------------------------------------------------
    # EN: Output sits one level above _Arcade, which is the MiSTer layout. It is
    #     derived rather than asked for, and printed before anything is written.
    # FR: La sortie se trouve un niveau au-dessus de _Arcade, structure MiSTer.
    #     Elle est deduite plutot que demandee, et affichee avant toute ecriture.
    # ---------------------------------------------------------------------------
    $outDir = Join-Path (Split-Path $arcFull -Parent) 'media'

    $lists    = @()
    $rootList = Join-Path $arcFull 'gamelist.xml'
    if (Test-Path -LiteralPath $rootList) { $lists += $rootList }

    $jobs.Add([pscustomobject]@{
        Name         = 'Arcade'
        RomRoot      = $arcFull
        MediaRoot    = $mediaRoot
        OutDir       = $outDir
        Gamelists    = $lists
        OnlyExt      = @('.mra')
        # EN: _Organized only duplicates the root set, _alternatives does not.
        # FR: _Organized ne fait que dupliquer la racine, _alternatives non.
        ExcludeDirs  = $CommonExcludeDirs + @('_Organized', 'cores')
        ExcludeFiles = @()
    })
}

if ($jobs.Count -eq 0) {
    Write-Host 'Nothing to process.' -ForegroundColor Yellow
    return
}

Write-Host ("Mode    : {0}" -f $PSCmdlet.ParameterSetName) -ForegroundColor Cyan
Write-Host ("Jobs    : {0}" -f $jobs.Count) -ForegroundColor Cyan
Write-Host ("Sources : {0} and {1}" -f $BoxDir, $ScreenDir) -ForegroundColor Cyan
Write-Host ("Output  : {0}" -f $jobs[0].OutDir) -ForegroundColor Cyan
Write-Host ''

# ===========================================================================
# EN: MAIN LOOP
# FR: BOUCLE PRINCIPALE
# ===========================================================================
$report  = New-Object System.Collections.Generic.List[object]
$orphans = New-Object System.Collections.Generic.List[object]
$Grand   = [ordered]@{ Roms = 0; Box = 0; Bg = 0; NoBox = 0; NoBg = 0; Skipped = 0; Purged = 0 }
$BySrc   = [ordered]@{ gamelist = 0; manual = 0; glname = 0; folder = 0; norm = 0; noplus = 0; prefix = 0; rprefix = 0; fuzzy = 0 }

$jobIndex = 0

foreach ($job in $jobs) {

    # ---------------------------------------------------------------------------
    # EN: The outer bar also covers indexing and XML parsing, which take seconds
    #     on a large arcade gamelist and would otherwise look like a freeze.
    # FR: La barre externe couvre aussi l'indexation et le parsing XML, qui
    #     prennent quelques secondes sur un gros gamelist arcade et
    #     ressembleraient sinon a un blocage.
    # ---------------------------------------------------------------------------
    $jobIndex++
    $jobPct = [int](100 * ($jobIndex - 1) / $jobs.Count)

    Write-Progress -Id 1 -Activity 'Deploying media' `
        -Status ("{0}  ({1}/{2})  indexing artwork" -f $job.Name, $jobIndex, $jobs.Count) `
        -PercentComplete $jobPct

    $boxIdx  = New-MediaIndex (Join-Path $job.MediaRoot $BoxDir)
    $shotIdx = New-MediaIndex (Join-Path $job.MediaRoot $ScreenDir)

    $gl = $null
    if ($job.Gamelists.Count -gt 0) {
        Write-Progress -Id 1 -Activity 'Deploying media' `
            -Status ("{0}  ({1}/{2})  reading gamelist" -f $job.Name, $jobIndex, $jobs.Count) `
            -PercentComplete $jobPct

        $gl = Read-Gamelist -ListPaths $job.Gamelists -BoxLeaf $BoxDir -ScreenLeaf $ScreenDir
        foreach ($e in $gl.Errors) { Write-Warning "[$($job.Name)] unreadable gamelist -> $e" }
    }

    foreach ($col in $boxIdx.Collisions)  { Write-Warning "[$($job.Name)] $BoxDir collision: $col" }
    foreach ($col in $shotIdx.Collisions) { Write-Warning "[$($job.Name)] $ScreenDir collision: $col" }

    # --- inventory / inventaire -------------------------------------------------
    Write-Progress -Id 1 -Activity 'Deploying media' `
        -Status ("{0}  ({1}/{2})  scanning ROMs" -f $job.Name, $jobIndex, $jobs.Count) `
        -PercentComplete $jobPct

    $allFiles = @(Get-ChildItem -LiteralPath $job.RomRoot -File -Recurse -ErrorAction SilentlyContinue)
    $rootLen  = $job.RomRoot.Length

    # EN: Folders holding a CD index file, their tracks are not ROMs. / FR: Dossiers contenant un index CD, leurs pistes ne sont pas des ROMs.
    $dirsWithIndex = @{}
    foreach ($f in $allFiles) {
        if ($IndexExt -contains $f.Extension.ToLower()) { $dirsWithIndex[$f.DirectoryName] = $true }
    }

    $roms = @($allFiles | Where-Object {
        $ext = $_.Extension.ToLower()

        if ($job.OnlyExt) {
            if ($job.OnlyExt -notcontains $ext) { return $false }
        }
        else {
            if ($IgnoreExt -contains $ext -or $CompanionExt -contains $ext) { return $false }
            if ($ConditionalCompanionExt -contains $ext -and $dirsWithIndex.ContainsKey($_.DirectoryName)) { return $false }
            foreach ($pat in $job.ExcludeFiles) { if ($_.Name -like $pat) { return $false } }
        }

        $relDir = $_.DirectoryName.Substring($rootLen).Trim('\')
        if ($relDir) {
            foreach ($seg in ($relDir -split '\\')) {
                if ($job.ExcludeDirs -contains $seg) { return $false }
            }
        }
        return $true
    })

    if ($roms.Count -eq 0) {
        Write-Verbose "[$($job.Name)] no ROM found, skipped"
        continue
    }

    if (-not (Test-Path -LiteralPath $job.OutDir)) {
        if ($PSCmdlet.ShouldProcess($job.OutDir, 'Create output folder')) {
            New-Item -ItemType Directory -Path $job.OutDir -Force | Out-Null
        }
    }

    # ---------------------------------------------------------------------------
    # EN: One listing of the output folder, then every existence test is a hash
    #     lookup. Comparison is ordinal but case insensitive, which matches
    #     Windows and is the safe choice on the case sensitive ext4 volume the
    #     MiSTer actually reads.
    # FR: Un seul listing du dossier de sortie, puis chaque test d'existence
    #     devient une recherche par hachage. La comparaison est ordinale mais
    #     insensible a la casse, ce qui correspond a Windows et reste le choix
    #     prudent sur le volume ext4 sensible a la casse que lit la MiSTer.
    # ---------------------------------------------------------------------------
    $existing = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($f in @(Get-ChildItem -LiteralPath $job.OutDir -File -ErrorAction SilentlyContinue)) {
        $existing.Add($f.Name) | Out-Null
    }

    $Stat       = [ordered]@{ Roms = 0; Box = 0; Bg = 0; NoBox = 0; NoBg = 0; Skipped = 0; Purged = 0 }
    $seenTarget = @{}

    # EN: Refreshed once per percent at most, see the note in the clean script.
    # FR: Rafraichi une fois par pourcent au plus, voir la note du script de nettoyage.
    $step = [Math]::Max(1, [int]($roms.Count / 100))

    foreach ($rom in $roms) {

        $Stat.Roms++; $Grand.Roms++
        $base = [IO.Path]::GetFileNameWithoutExtension($rom.Name)
        $dir  = $rom.DirectoryName

        if ($Stat.Roms % $step -eq 0) {
            Write-Progress -Id 2 -ParentId 1 -Activity "Copying artwork for $($job.Name)" `
                -Status ("{0} / {1}   {2}" -f $Stat.Roms, $roms.Count, $base) `
                -PercentComplete ([int](100 * $Stat.Roms / $roms.Count))
        }

        $boxHit  = Resolve-Media -RomPath $rom.FullName -RomBase $base -RomDir $dir `
                                 -SystemName $job.Name -Gl $gl -Idx $boxIdx  -Kind Box
        $shotHit = Resolve-Media -RomPath $rom.FullName -RomBase $base -RomDir $dir `
                                 -SystemName $job.Name -Gl $gl -Idx $shotIdx -Kind Shot

        # EN: Flat output means two ROMs can aim at one target name. / FR: Une sortie a plat permet a deux ROMs de viser un meme nom de cible.
        if ($seenTarget.ContainsKey($base)) {
            Write-Warning ("[{0}] target collision: '{1}' and '{2}'" -f $job.Name, $rom.Name, $seenTarget[$base])
        }
        else {
            $seenTarget[$base] = $rom.Name
        }

        if ($boxHit) {
            $ext   = [IO.Path]::GetExtension($boxHit.Path).ToLower()
            $twins = Get-TwinNames -Base $base -KeepExt $ext
            if ((Copy-Media -Source $boxHit.Path -TargetDir $job.OutDir -TargetName "$base$ext" `
                            -TwinNames $twins -Existing $existing) -eq 'copied') {
                $Stat.Box++; $Grand.Box++
            }
            else { $Stat.Skipped++; $Grand.Skipped++ }
            $BySrc[$boxHit.Match]++
        }
        else {
            $Stat.NoBox++; $Grand.NoBox++
            Write-Verbose "[$($job.Name)] no box art for: $base"
        }

        if ($shotHit) {
            $ext   = [IO.Path]::GetExtension($shotHit.Path).ToLower()
            $twins = Get-TwinNames -Base "$base$BgSuffix" -KeepExt $ext
            if ((Copy-Media -Source $shotHit.Path -TargetDir $job.OutDir -TargetName "$base$BgSuffix$ext" `
                            -TwinNames $twins -Existing $existing) -eq 'copied') {
                $Stat.Bg++; $Grand.Bg++
            }
            else { $Stat.Skipped++; $Grand.Skipped++ }
        }
        else {
            $Stat.NoBg++; $Grand.NoBg++
            Write-Verbose "[$($job.Name)] no snapshot for: $base"
        }

        if ($ReportCsv) {
            $report.Add([pscustomobject]@{
                System    = $job.Name
                Rom       = $rom.Name
                SubFolder = if ($dir -ne $job.RomRoot) { Split-Path $dir -Leaf } else { '' }
                GlName    = if ($gl -and $gl.GameName.ContainsKey($rom.FullName)) { $gl.GameName[$rom.FullName] } else { '' }
                BoxSource = if ($boxHit)  { [IO.Path]::GetFileName($boxHit.Path) }  else { '' }
                BoxMatch  = if ($boxHit)  { $boxHit.Match }  else { 'MISSING' }
                BgSource  = if ($shotHit) { [IO.Path]::GetFileName($shotHit.Path) } else { '' }
                BgMatch   = if ($shotHit) { $shotHit.Match } else { 'MISSING' }
            })
        }
    }

    Write-Progress -Id 2 -Activity 'Copying artwork' -Completed

    # ---------------------------------------------------------------------------
    # EN: The optimized cache holds frontend-generated thumbnails of the very
    #     files we just replaced, so it is stale by definition. Emptied per job,
    #     never created, and left alone in incremental mode where nothing was
    #     replaced.
    # FR: Le cache optimized contient les vignettes generees par le frontend a
    #     partir des fichiers qu'on vient de remplacer, il est donc perime par
    #     definition. Vide par travail, jamais cree, et laisse intact en mode
    #     incrementiel ou rien n'a ete remplace.
    # ---------------------------------------------------------------------------
    $optDir = Join-Path $job.OutDir 'optimized'
    if (-not $NoOverwrite -and (Test-Path -LiteralPath $optDir)) {
        $cached = @(Get-ChildItem -LiteralPath $optDir -Force -ErrorAction SilentlyContinue)
        if ($cached.Count -gt 0) {
            if ($PSCmdlet.ShouldProcess($optDir, "Empty optimized cache, $($cached.Count) items")) {
                $cached | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
            }
            $Stat.Purged   = $cached.Count
            $Grand.Purged += $cached.Count
        }
    }

    if ($ReportCsv) {
        foreach ($idx in @($boxIdx, $shotIdx)) {
            foreach ($mediaPath in $idx.Primary.Values) {
                if (-not $idx.Used.ContainsKey($mediaPath)) {
                    $orphans.Add([pscustomobject]@{
                        System = $job.Name
                        Kind   = Split-Path (Split-Path $mediaPath -Parent) -Leaf
                        File   = [IO.Path]::GetFileName($mediaPath)
                    })
                }
            }
        }
    }

    $glInfo = if ($gl) { "gl=$($gl.Entries)/h$($gl.Inherited)" } else { 'gl=none' }
    $line = "[{0,-22}] roms={1,-5} box={2,-5} bg={3,-5} no-box={4,-4} no-bg={5,-4} {6,-14} skip={7,-4} cache={8}" -f `
            $job.Name, $Stat.Roms, $Stat.Box, $Stat.Bg, $Stat.NoBox, $Stat.NoBg, $glInfo, $Stat.Skipped, $Stat.Purged
    $color = if ($Stat.NoBox -gt 0 -or $Stat.NoBg -gt 0) { 'Yellow' } else { 'Gray' }
    Write-Host $line -ForegroundColor $color
}

# ===========================================================================
# EN: SUMMARY
# FR: SYNTHESE
# ===========================================================================
Write-Progress -Id 1 -Activity 'Deploying media' -Completed

Write-Host ''
Write-Host ("TOTAL : {0} roms | {1} box | {2} bg | {3} without box | {4} without bg | {5} skipped | {6} cache entries purged" -f `
            $Grand.Roms, $Grand.Box, $Grand.Bg, $Grand.NoBox, $Grand.NoBg, $Grand.Skipped, $Grand.Purged) -ForegroundColor Cyan

Write-Host ("MATCH : gamelist={0} manual={1} glname={2} folder={3} norm={4} noplus={5} prefix={6} rprefix={7} fuzzy={8}" -f `
            $BySrc.gamelist, $BySrc.manual, $BySrc.glname, $BySrc.folder, $BySrc.norm,
            $BySrc.noplus, $BySrc.prefix, $BySrc.rprefix, $BySrc.fuzzy) -ForegroundColor DarkCyan

$heuristic = $BySrc.prefix + $BySrc.rprefix + $BySrc.fuzzy
if ($heuristic -gt 0) {
    Write-Host ("        {0} heuristic matches to review in the report: prefix, rprefix, fuzzy" -f $heuristic) -ForegroundColor Yellow
}

if ($ReportCsv -and $report.Count) {
    # EN: Written even under -WhatIf, the report being the point of a dry run.
    # FR: Ecrit meme sous -WhatIf, le rapport etant l'objet meme d'un essai a blanc.
    $report | Export-Csv -LiteralPath $ReportCsv -NoTypeInformation -Encoding UTF8 -Delimiter ';' -WhatIf:$false
    Write-Host "Report  : $ReportCsv"

    if ($orphans.Count) {
        $orphPath = ($ReportCsv -replace '\.csv$', '') + '-orphans.csv'
        $orphans | Export-Csv -LiteralPath $orphPath -NoTypeInformation -Encoding UTF8 -Delimiter ';' -WhatIf:$false
        Write-Host "Orphans : $orphPath, $($orphans.Count) files"
    }
}
