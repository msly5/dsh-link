import fs from 'node:fs';
import {execFileSync} from 'node:child_process';

export function assertPrivate(file) {
  const stat = fs.statSync(file);
  if (process.platform !== 'win32') {
    if ((stat.mode & 0o077) !== 0 || stat.uid !== process.getuid()) throw new Error('Use an owned 0700 directory and private 0600 files.');
    return;
  }
  // Compare SIDs, not localized account names. Never print the ACL or file contents.
  const script = `$ErrorActionPreference='Stop'; if ([IO.Directory]::Exists($env:DSH_PRIVATE_PATH)) { $acl=[IO.Directory]::GetAccessControl($env:DSH_PRIVATE_PATH) } else { $acl=[IO.File]::GetAccessControl($env:DSH_PRIVATE_PATH) }; $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value; $owner=$acl.GetOwner([Security.Principal.SecurityIdentifier]).Value; if ($owner -ne $sid) { exit 1 }; foreach ($rule in $acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])) { if ($rule.AccessControlType -eq 'Allow' -and $rule.IdentityReference.Value -notin @($sid,'S-1-5-18','S-1-5-32-544')) { exit 1 } }`;
  try { execFileSync('powershell.exe', ['-NoProfile','-NonInteractive','-Command',script], {env:{...process.env,DSH_PRIVATE_PATH:file},stdio:'ignore',windowsHide:true,timeout:15000}); }
  catch { throw new Error('Private configuration ACL must permit only your Windows account, SYSTEM and Administrators. Run scripts/bootstrap.py.'); }
}
