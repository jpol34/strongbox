FROM mcr.microsoft.com/powershell:latest

RUN pwsh -NoProfile -Command " \
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force | Out-Null; \
    Install-Module -Name Pode -Scope AllUsers -Force -AllowClobber; \
    Install-Module -Name PSSQLite -Scope AllUsers -Force -AllowClobber; \
    "

COPY . /app/server

VOLUME /data
EXPOSE 8080

ENTRYPOINT ["pwsh", "-NoProfile", "-File", "/app/server/Start-StrongboxSyncServer.ps1"]
