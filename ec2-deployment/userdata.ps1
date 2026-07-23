<powershell>
# Install IIS Web Server
Import-Module ServerManager
Add-WindowsFeature Web-Server -IncludeManagementTools

# Create a simple homepage
New-Item -Path 'C:\inetpub\wwwroot\index.html' -ItemType File -Value '<h1>Hello from Windows IIS VM</h1>' -Force
</powershell>
