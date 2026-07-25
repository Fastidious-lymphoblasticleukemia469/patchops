# lab-host — shared SSH + Python3 base image for all patchops lab containers
# (the aptly mirror host and the 5 ansible-managed ubuntu hosts). Packages are
# installed once at build time (cached), instead of on every container boot
# like the old inline `command:` blocks in compose.lab.yml did.
#
# The user/UID differ per host (aptly needs a fixed UID 115 to match
# roles/setup_aptly/defaults/main.yml; ubuntu1-5 don't care), so both are
# build args — see compose.lab.yml for the per-service values.
FROM ubuntu:24.04

ARG SSH_USER=ansible
ARG SSH_PASS=ansible
# Leave unset to let useradd pick a UID automatically (ubuntu1-5's case).
ARG SSH_UID=
ARG SSH_PUBKEY

RUN apt-get update -qq && \
    apt-get install -y -qq openssh-server python3 sudo && \
    rm -rf /var/lib/apt/lists/* && \
    mkdir -p /run/sshd

RUN useradd ${SSH_UID:+-u "$SSH_UID"} -m -s /bin/bash "${SSH_USER}" && \
    echo "${SSH_USER}:${SSH_PASS}" | chpasswd && \
    echo "${SSH_USER} ALL=(ALL:ALL) NOPASSWD:ALL" > "/etc/sudoers.d/${SSH_USER}" && \
    mkdir -p "/home/${SSH_USER}/.ssh" && \
    echo "${SSH_PUBKEY}" > "/home/${SSH_USER}/.ssh/authorized_keys" && \
    chmod 700 "/home/${SSH_USER}/.ssh" && \
    chmod 600 "/home/${SSH_USER}/.ssh/authorized_keys" && \
    chown -R "${SSH_USER}:${SSH_USER}" "/home/${SSH_USER}/.ssh"

EXPOSE 22
# sshd must run as root (privilege separation needs it to setuid to the
# login user after auth, and to bind/manage the listening socket) — a
# non-root USER would break the container's entire purpose, so this is an
# accepted exception to the usual non-root-user rule for these lab images.
HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
  CMD bash -c 'echo > /dev/tcp/127.0.0.1/22 || exit 1'
CMD ["/usr/sbin/sshd", "-D"]
