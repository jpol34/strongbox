FROM debian:bookworm-slim

ARG TARGETARCH
ARG PWSH_VERSION=7.4.6

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl libicu72 libsqlite3-0 liblttng-ust1 \
    && case "$TARGETARCH" in \
        amd64) PWSH_ARCH=x64 ;; \
        arm64) PWSH_ARCH=arm64 ;; \
        *) echo "unsupported TARGETARCH: $TARGETARCH" >&2; exit 1 ;; \
    esac \
    && curl -fsSL -o /tmp/pwsh.tar.gz \
        "https://github.com/PowerShell/PowerShell/releases/download/v${PWSH_VERSION}/powershell-${PWSH_VERSION}-linux-${PWSH_ARCH}.tar.gz" \
    && mkdir -p /opt/microsoft/powershell/7 \
    && tar -xzf /tmp/pwsh.tar.gz -C /opt/microsoft/powershell/7 \
    && chmod +x /opt/microsoft/powershell/7/pwsh \
    && ln -s /opt/microsoft/powershell/7/pwsh /usr/bin/pwsh \
    && rm /tmp/pwsh.tar.gz \
    && apt-get purge -y curl && apt-get autoremove -y && rm -rf /var/lib/apt/lists/*

RUN pwsh -NoProfile -Command " \
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force | Out-Null; \
    Install-Module -Name Pode -Scope AllUsers -Force -AllowClobber; \
    "

COPY . /app/server

VOLUME /data
EXPOSE 8080

ENTRYPOINT ["pwsh", "-NoProfile", "-File", "/app/server/Start-StrongboxSyncServer.ps1"]
