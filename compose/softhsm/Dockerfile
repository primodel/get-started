# SoftHSM init sidecar — a REAL PKCS#11/Cryptoki token for the get-started stack's KEK, not
# `PRIMODEL_KEK=none` and not raw key material in an env var.
#
# SoftHSM's PKCS#11 module is a shared library the app process loads in-process (Net.Pkcs11Interop
# dlopen's it) — there is no HSM network protocol to run as a normal "service" sidecar. So this
# container's job is a one-shot INIT: create the SoftHSM token (so the app can log in) and publish
# the .so module + its config onto bind-mounted volumes the `primodel` container also mounts. The
# app itself then generates the AES KEK object on the token on first boot
# (PRIMODEL_KEK_PKCS11_CREATE_IF_MISSING=true) — see entrypoint.sh and the compose comments.
#
# debian:bookworm-slim matches the Debian release under mcr.microsoft.com/dotnet/aspnet:10.0
# (also Debian 12/bookworm), so libsofthsm2.so's glibc/libssl ABI lines up with the primodel
# container it gets bind-mounted into.
FROM debian:bookworm-slim

RUN apt-get update \
 && apt-get install -y --no-install-recommends softhsm2 \
 && rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
