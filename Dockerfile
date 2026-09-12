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

FROM nrfutil AS build-base
# Install the NCS SDK + matching toolchain into NCS_INSTALL_DIR
ARG NCS_VERSION=v3.1.1
ARG NCS_INSTALL_DIR=/opt/nrf
RUN set -eux; \
	nrfutil sdk-manager install "${NCS_VERSION}" --install-dir "${NCS_INSTALL_DIR}" && \
	rm -rf "${NCS_INSTALL_DIR}/downloads"

ENV NCS_VERSION=${NCS_VERSION}
ENV NCS_INSTALL_DIR=${NCS_INSTALL_DIR}

FROM build-base AS build-base-zb-r23
# Add the Zigbee R23 add-on on top of the NCS SDK and toolchain
# NB: Zigbee R23 add-on releases require specific NCS versions
# so ZB_R23_VERSION and NCS_VERSION must be a matching pair
ARG ZB_R23_VERSION=v1.4.0
RUN set -eux; \
	git clone --branch "${ZB_R23_VERSION}" --depth 1 https://github.com/nrfconnect/ncs-zigbee "${NCS_INSTALL_DIR}/${NCS_VERSION}/ncs-zigbee"; \
	nrfutil sdk-manager toolchain launch \
		--ncs-version "${NCS_VERSION}" --install-dir "${NCS_INSTALL_DIR}" \
		--chdir "${NCS_INSTALL_DIR}/${NCS_VERSION}" \
		-- bash -c 'west config manifest.path ncs-zigbee && west update'
ENV ZB_R23_VERSION=${ZB_R23_VERSION}