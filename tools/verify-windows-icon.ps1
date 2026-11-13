[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $ExecutablePath,
    [string] $IconPath = (Join-Path $PSScriptRoot '../windows/runner/resources/app_icon.ico')
)
$ErrorActionPreference = 'Stop'
if (!$IsWindows -and $PSVersionTable.PSEdition -eq 'Core') { throw 'Windows icon verification requires Windows.' }
if (!('ClientIconResourceReader' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
public static class ClientIconResourceReader {
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    public static extern IntPtr LoadLibraryExW(string file, IntPtr unused, uint flags);
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool FreeLibrary(IntPtr module);
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    static extern IntPtr FindResourceW(IntPtr module, IntPtr name, IntPtr type);
    [DllImport("kernel32.dll", SetLastError=true)]
    static extern uint SizeofResource(IntPtr module, IntPtr resource);
    [DllImport("kernel32.dll", SetLastError=true)]
    static extern IntPtr LoadResource(IntPtr module, IntPtr resource);
    [DllImport("kernel32.dll", SetLastError=true)]
    static extern IntPtr LockResource(IntPtr resource);
    public static byte[] Read(IntPtr module, int type, int id) {
        IntPtr resource = FindResourceW(module, new IntPtr(id), new IntPtr(type));
        if(resource == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
        uint size = SizeofResource(module, resource);
        IntPtr data = LockResource(LoadResource(module, resource));
        if(data == IntPtr.Zero || size == 0) throw new Win32Exception(Marshal.GetLastWin32Error());
        byte[] bytes = new byte[checked((int)size)];
        Marshal.Copy(data, bytes, 0, bytes.Length);
        return bytes;
    }
}
'@
}
function Icon-Hash([byte[]] $Bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return [Convert]::ToBase64String($sha.ComputeHash($Bytes)) } finally { $sha.Dispose() }
}
$ico = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $IconPath).Path)
if ($ico.Length -lt 6 -or [BitConverter]::ToUInt16($ico, 2) -ne 1) { throw 'Invalid ICO file.' }
$count = [BitConverter]::ToUInt16($ico, 4)
$expected = @{}
for ($i = 0; $i -lt $count; $i++) {
    $offset = 6 + 16 * $i
    $length = [BitConverter]::ToUInt32($ico, $offset + 8)
    $start = [BitConverter]::ToUInt32($ico, $offset + 12)
    $data = New-Object byte[] $length
    [Buffer]::BlockCopy($ico, $start, $data, 0, $length)
    $expected["$($ico[$offset])x$($ico[$offset + 1])"] = Icon-Hash $data
}
# Load only resource data; never execute code from the application being checked.
$module = [ClientIconResourceReader]::LoadLibraryExW((Resolve-Path -LiteralPath $ExecutablePath).Path, [IntPtr]::Zero, 0x22)
if ($module -eq [IntPtr]::Zero) { throw 'Could not load executable resources.' }
try {
    $group = [ClientIconResourceReader]::Read($module, 14, 101)
    if ([BitConverter]::ToUInt16($group, 4) -ne $count) { throw 'Executable has an outdated icon frame count.' }
    for ($i = 0; $i -lt $count; $i++) {
        $offset = 6 + 14 * $i
        $id = [BitConverter]::ToUInt16($group, $offset + 12)
        $key = "$($group[$offset])x$($group[$offset + 1])"
        $data = [ClientIconResourceReader]::Read($module, 3, $id)
        if (!$expected.ContainsKey($key) -or (Icon-Hash $data) -ne $expected[$key]) {
            throw "Executable contains an outdated icon frame: $key"
        }
    }
    Write-Host "PASS executable icon matches source ($count resolutions)."
} finally { [void][ClientIconResourceReader]::FreeLibrary($module) }
