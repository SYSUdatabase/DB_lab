# Grant or revoke "Log on as a batch job" (SeBatchLogonRight) for one local account SID.
# The runtime scheduled task stores a password and starts as a batch logon; some Windows
# editions (seen on Windows 10 Home) do not grant this right automatically, failing with 0xC000015B.
if (-not ('TokenHubLsa' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class TokenHubLsa {
    [StructLayout(LayoutKind.Sequential)] struct Text { public ushort Length, MaximumLength; [MarshalAs(UnmanagedType.LPWStr)] public string Buffer; }
    [StructLayout(LayoutKind.Sequential)] struct Attributes { public int Length; public IntPtr Root, Name; public uint Flags; public IntPtr Descriptor, Quality; }
    [DllImport("advapi32.dll")] static extern uint LsaOpenPolicy(IntPtr system, ref Attributes attributes, uint access, out IntPtr policy);
    [DllImport("advapi32.dll")] static extern uint LsaAddAccountRights(IntPtr policy, byte[] sid, Text[] rights, uint count);
    [DllImport("advapi32.dll")] static extern uint LsaRemoveAccountRights(IntPtr policy, byte[] sid, bool all, Text[] rights, uint count);
    [DllImport("advapi32.dll")] static extern uint LsaClose(IntPtr policy);
    public static uint SetBatchLogon(byte[] sid, bool grant) {
        var attributes = new Attributes { Length = Marshal.SizeOf(typeof(Attributes)) };
        IntPtr policy;
        uint status = LsaOpenPolicy(IntPtr.Zero, ref attributes, 0x811, out policy);
        if (status != 0) return status;
        var rights = new[] { new Text { Buffer = "SeBatchLogonRight", Length = 34, MaximumLength = 36 } };
        try { status = grant ? LsaAddAccountRights(policy, sid, rights, 1) : LsaRemoveAccountRights(policy, sid, false, rights, 1); }
        finally { LsaClose(policy); }
        // 0xC0000034: the SID holds no rights, so a revoke is already satisfied.
        return (!grant && status == 0xC0000034) ? 0 : status;
    }
}
'@
}
function Set-BatchLogonRight([string]$Sid, [switch]$Revoke) {
    $identifier = New-Object Security.Principal.SecurityIdentifier($Sid)
    $bytes = New-Object byte[] $identifier.BinaryLength
    $identifier.GetBinaryForm($bytes, 0)
    $status = [TokenHubLsa]::SetBatchLogon($bytes, -not $Revoke)
    if ($status -ne 0) { throw ('SeBatchLogonRight update failed: NTSTATUS 0x{0:X8}' -f $status) }
}
