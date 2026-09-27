# display-auto.ps1 — choisit l'écran de bureau du PC-RTX5080 selon ce qui est branché.
#   status : affiche les chemins d'affichage (actifs / disponibles)
#   auto   : Dell présent sur la RTX -> Dell seul ; sinon -> écran virtuel (VDD) seul
# Doit tourner dans la session console (tâche planifiée à l'ouverture de session), pas en session 0 SSH.
param([ValidateSet('status','auto')][string]$Mode = 'status',
      [string]$Physical = 'DEL430F', [string]$Virtual = 'MTT1337',
      [string]$Log = 'C:\ProgramData\display-auto\display-auto.log')

Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public static class DC {
  [StructLayout(LayoutKind.Sequential)] public struct LUID { public uint Lo; public int Hi; }
  [StructLayout(LayoutKind.Sequential)] public struct RATIONAL { public uint N; public uint D; }
  [StructLayout(LayoutKind.Sequential)] public struct SRC { public LUID adapterId; public uint id; public uint modeInfoIdx; public uint statusFlags; }
  [StructLayout(LayoutKind.Sequential)] public struct TGT { public LUID adapterId; public uint id; public uint modeInfoIdx; public uint outputTechnology; public uint rotation; public uint scaling; public RATIONAL refreshRate; public uint scanLineOrdering; public int targetAvailable; public uint statusFlags; }
  [StructLayout(LayoutKind.Sequential)] public struct PATH { public SRC src; public TGT tgt; public uint flags; }
  [StructLayout(LayoutKind.Sequential)] public struct MODE { public uint infoType; public uint id; public LUID adapterId; [MarshalAs(UnmanagedType.ByValArray, SizeConst=48)] public byte[] data; }
  [StructLayout(LayoutKind.Sequential)] public struct HDR { public uint type; public uint size; public LUID adapterId; public uint id; }
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] public struct TNAME { public HDR h; public uint flags; public uint tech; public ushort mfg; public ushort prod; public uint conn;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst=64)] public string friendly; [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string path; }
  [DllImport("user32.dll")] public static extern int GetDisplayConfigBufferSizes(uint f, out uint np, out uint nm);
  [DllImport("user32.dll")] public static extern int QueryDisplayConfig(uint f, ref uint np, [Out] PATH[] p, ref uint nm, [Out] MODE[] m, IntPtr t);
  [DllImport("user32.dll")] public static extern int DisplayConfigGetDeviceInfo(ref TNAME n);
  [DllImport("user32.dll")] public static extern int SetDisplayConfig(uint np, [In] PATH[] p, uint nm, [In] MODE[] m, uint f);
  public static PATH[] Query(uint f) { uint np, nm; GetDisplayConfigBufferSizes(f, out np, out nm);
    var p = new PATH[np]; var m = new MODE[nm]; int r = QueryDisplayConfig(f, ref np, p, ref nm, m, IntPtr.Zero);
    if (r != 0) throw new Exception("QueryDisplayConfig " + r); Array.Resize(ref p, (int)np); return p; }
  public static string Name(PATH p) { var n = new TNAME(); n.h.type = 2; n.h.size = (uint)Marshal.SizeOf(typeof(TNAME));
    n.h.adapterId = p.tgt.adapterId; n.h.id = p.tgt.id; return DisplayConfigGetDeviceInfo(ref n) == 0 ? n.friendly + "|" + n.path : "?"; }
  // Active ce seul chemin ; modes laissés à la base de persistance de Windows (résolution/cadence mémorisées).
  // SDC_APPLY | SDC_USE_SUPPLIED_DISPLAY_CONFIG | SDC_ALLOW_CHANGES | SDC_SAVE_TO_DATABASE
  public static int Only(PATH p) { p.flags = 1; p.src.modeInfoIdx = 0xFFFFFFFF; p.tgt.modeInfoIdx = 0xFFFFFFFF;
    return SetDisplayConfig(1, new PATH[] { p }, 0, null, 0x80 | 0x20 | 0x400 | 0x200); }
}
'@

function Say($m) { $l = "{0:yyyy-MM-dd HH:mm:ss} [{1}] {2}" -f (Get-Date), $env:USERNAME, $m; Write-Output $l
  if ($Mode -eq 'auto') { New-Item -ItemType Directory -Force (Split-Path $Log) | Out-Null; Add-Content $Log $l } }

$QDC_ALL = 1; $QDC_ACTIVE = 2
function Targets {  # une entrée par écran disponible (premier chemin trouvé), avec l'état actif
  $all = [DC]::Query($QDC_ALL) | ? { $_.tgt.targetAvailable -ne 0 }
  $act = [DC]::Query($QDC_ACTIVE)
  $seen = @{}
  foreach ($p in $all) { $k = "$($p.tgt.adapterId.Lo)/$($p.tgt.id)"; if ($seen[$k]) { continue }
    $n = [DC]::Name($p)
    $isAct = [bool]($act | ? { $_.tgt.adapterId.Lo -eq $p.tgt.adapterId.Lo -and $_.tgt.id -eq $p.tgt.id })
    $seen[$k] = [pscustomobject]@{ Name = $n; Active = $isAct; Path = $p } }
  $seen.Values
}

if ($Mode -eq 'auto') { Start-Sleep 3 }  # laisse le pilote NVIDIA énumérer le DisplayPort après l'ouverture de session

$t = @(Targets)
if ($Mode -eq 'status') { $t | % { "{0,-6} {1}" -f $(if ($_.Active) {'ACTIF'} else {'-'}), $_.Name }; return }

$phys = $t | ? { $_.Name -match $Physical } | Select-Object -First 1
$virt = $t | ? { $_.Name -match $Virtual }  | Select-Object -First 1
$want = if ($phys) { $phys } elseif ($virt) { $virt } else { $null }
if (-not $want) { Say "aucun écran disponible, rien à faire"; return }
$others = @($t | ? { $_ -ne $want -and $_.Active })
if ($want.Active -and $others.Count -eq 0) { Say "déjà OK : $($want.Name) seul"; return }

# Flux Moonlight en cours : Sunshine gère lui-même l'affichage (ensure_only_display sur le VDD), ne rien toucher.
if (Get-NetUDPEndpoint -LocalPort 47998,47999,48000 -ErrorAction SilentlyContinue) { Say "flux Sunshine en cours, rien à faire"; return }
$r = [DC]::Only($want.Path)
Say ("bascule -> {0} seul (avant : {1}) : code {2}" -f $want.Name, (($t | ? Active | % Name) -join ', '), $r)
