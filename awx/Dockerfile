# Custom AWX Image for Docker Compose Standalone
# Fixes: K8s settings error, receptor full path, podman for EE isolation,
#        docker-ce-cli for EE image pre-loading, controlplane/default instance groups
#
# Multi-arch: build with `docker buildx build --platform linux/amd64,linux/arm64`

ARG AWX_VERSION=24.6.1

FROM quay.io/ansible/receptor:v1.6.5 AS receptor
FROM quay.io/ansible/awx:${AWX_VERSION}

USER root

# Copy receptor binary
COPY --from=receptor /usr/bin/receptor /usr/local/bin/receptor

# docker-ce-cli: AWX uses PROCESS_ISOLATION_EXECUTABLE=docker to launch EE containers
# via the host Docker socket — no Podman needed.
# --disablerepo="copr:*" skips the broken Rsyslog Copr repo shipped in the base image.
RUN dnf install -y dnf-plugins-core --disablerepo="copr:*" && \
    dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo && \
    dnf install -y docker-ce-cli --disablerepo="copr:*" && \
    dnf clean all

# Fix hardcoded podman in EE job runner — use settings.PROCESS_ISOLATION_EXECUTABLE instead.
# AWX 24.x ships with "podman" hardcoded in build_execution_environment_params(); this
# patch makes it respect the setting so docker (or any other runtime) works correctly.
RUN sed -i 's/"process_isolation_executable": "podman",  # need to provide, runner enforces default via argparse/"process_isolation_executable": settings.PROCESS_ISOLATION_EXECUTABLE,  # read from settings, not hardcoded/' \
    /var/lib/awx/venv/awx/lib/python3.11/site-packages/awx/main/tasks/jobs.py

# Create required directories
RUN mkdir -p /var/run/receptor /etc/receptor /var/lib/awx

# receptor.conf — use full path because venv bin dir is not on $PATH
RUN cat > /etc/receptor/receptor.conf << 'RECEPTORCONF'
---
- node:
    id: awx
- local-only:
    local: true
- control-service:
    service: control
    filename: /var/run/receptor/receptor.sock
- work-command:
    worktype: local
    command: /var/lib/awx/venv/awx/bin/ansible-runner
    params: worker
    allowruntimeparams: true
RECEPTORCONF
