# syntax=docker/dockerfile:1

ARG NCS_VERSION=v3.1.1
ARG NCS_INSTALL_DIR=/opt/nrf
# Which builder stage `staging`/`result` copy from: install-sdk (plain NCS SDK
# + toolchain) or install-zb-addon (install-sdk plus the Zigbee R23 add-on)
ARG VARIANT=install-sdk

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

FROM nrfutil AS install-sdk
# Install the NCS SDK + matching toolchain into NCS_INSTALL_DIR
ARG NCS_VERSION
ARG NCS_INSTALL_DIR
RUN set -eux; \
	nrfutil sdk-manager install "${NCS_VERSION}" --install-dir "${NCS_INSTALL_DIR}" && \
	rm -rf "${NCS_INSTALL_DIR}/downloads"

ENV NCS_VERSION=${NCS_VERSION}
ENV NCS_INSTALL_DIR=${NCS_INSTALL_DIR}
ENV ZEPHYR_BASE=${NCS_INSTALL_DIR}/${NCS_VERSION}/zephyr
ENV LD_LIBRARY_PATH=""

# Put west and toolchain on PATH and register with CMake
RUN set -eux; \
	nrfutil sdk-manager toolchain env \
		--ncs-version "${NCS_VERSION}" \
		--install-dir "${NCS_INSTALL_DIR}" \
		--as-script sh > /etc/profile.d/nrf-toolchain.sh; \
	echo "export ZEPHYR_BASE=${ZEPHYR_BASE}" >> /etc/profile.d/nrf-toolchain.sh; \
	. /etc/profile.d/nrf-toolchain.sh; \
	cd "${NCS_INSTALL_DIR}/${NCS_VERSION}" && west zephyr-export

FROM install-sdk AS install-zb-addon
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

FROM ${VARIANT} AS staging

# reduce image size
RUN set -eux; \
	NCS_DIR="${NCS_INSTALL_DIR}/${NCS_VERSION}"; \
	for repo_dir in "${NCS_DIR}/nrf" "${NCS_DIR}/nrfxlib" "${ZEPHYR_BASE}"; do \
		remote_name="$(git -C "${repo_dir}" remote | head -n1)"; \
		remote_url="$(git -C "${repo_dir}" remote get-url "${remote_name}")"; \
		tag="$(git -C "${repo_dir}" describe --tags --exact-match)"; \
		rm -rf "${repo_dir}"; \
		git clone --branch "${tag}" --depth 1 --recursive --shallow-submodules "${remote_url}" "${repo_dir}"; \
	done; \
	. /etc/profile.d/nrf-toolchain.sh; \
	cd "${NCS_DIR}" && west update

FROM nrfutil AS result
ARG NCS_VERSION
ARG NCS_INSTALL_DIR
COPY --from=staging ${NCS_INSTALL_DIR} ${NCS_INSTALL_DIR}
COPY --from=staging /etc/profile.d/nrf-toolchain.sh /etc/profile.d/nrf-toolchain.sh
COPY --from=staging /root/.cmake /root/.cmake

ENV NCS_VERSION=${NCS_VERSION}
ENV NCS_INSTALL_DIR=${NCS_INSTALL_DIR}
ENV ZEPHYR_BASE=${NCS_INSTALL_DIR}/${NCS_VERSION}/zephyr
ENV LD_LIBRARY_PATH=""
