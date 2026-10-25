"""Create a private configuration directory before any credential is written."""
import os
import subprocess

def protect_directory(directory):
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    if os.name == 'nt':
        # Use Windows PowerShell's .NET Framework API directly. A parent pwsh
        # process can otherwise inject incompatible modules via PSModulePath.
        script = "$ErrorActionPreference='Stop'; $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User; $acl=[Security.AccessControl.DirectorySecurity]::new(); $acl.SetOwner($sid); $acl.SetAccessRuleProtection($true,$false); $rule=[Security.AccessControl.FileSystemAccessRule]::new($sid,'FullControl','ContainerInherit,ObjectInherit','None','Allow'); $acl.AddAccessRule($rule); [IO.Directory]::SetAccessControl($env:DSH_PRIVATE_PATH,$acl)"
        subprocess.run(['powershell.exe','-NoProfile','-NonInteractive','-Command',script], env={**os.environ,'DSH_PRIVATE_PATH':str(directory)}, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    else:
        directory.chmod(0o700)
