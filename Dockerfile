# syntax=docker/dockerfile:1

FROM debian:trixie AS nrfutil

# Host packages not covered by the NCS toolchain bundle installed below
ARG DEBIAN_FRONTEND=noninteractive
RUN set -eux; \
	apt-get update; \
	apt-get install -y --no-install-recommends \
		ca-certificates \
		curl \
		git \
		libsdl2-dev \
		python3-venv \
	; \
	apt-get clean; \
	rm -rf /var/lib/apt/lists/*

# Install nrfutil and use it to install sdk-manager
ARG TARGETARCH
RUN set -eux; \
	case "${TARGETARCH}" in \
		amd64) nrfutil_arch=x86_64-unknown-linux-gnu ;; \
		arm64) nrfutil_arch=aarch64-unknown-linux-gnu ;; \
		*) echo "Unsupported architecture: ${TARGETARCH}" >&2; exit 1 ;; \
	esac; \
	base_url="https://files.nordicsemi.com/artifactory/swtools/external/nrfutil/executables/${nrfutil_arch}"; \
	curl -fsSL -o /usr/local/bin/nrfutil "${base_url}/nrfutil"; \
	curl -fsSL -o /tmp/nrfutil.sha256 "${base_url}/nrfutil.sha256"; \
	echo "$(cat /tmp/nrfutil.sha256)  /usr/local/bin/nrfutil" | sha256sum -c -; \
	rm -f /tmp/nrfutil.sha256; \
	chmod 755 /usr/local/bin/nrfutil; \
	nrfutil install sdk-manager --force

FROM nrfutil AS buld_base
# Install the NCS SDK + matching toolchain into NCS_INSTALL_DIR
ARG NCS_VERSION=v3.1.1
ARG NCS_INSTALL_DIR=/opt/nrf
RUN set -eux; \	
	nrfutil sdk-manager install "${NCS_VERSION}" --install-dir "${NCS_INSTALL_DIR}"
ENV NCS_VERSION=${NCS_VERSION}
ENV NCS_INSTALL_DIR=${NCS_INSTALL_DIR}