# SPDX-License-Identifier: MIT
# ROKFOSS unkernel container image.
#
# Built by .github/workflows/docker.yml from the `release` artifact of the
# Release workflow. Nothing is compiled here: that artifact already carries
# the Linux wasm kernel, the npm package (dist/) and the distro images built
# from the same commit. The CLI takes a distro image by path (--distro FILE),
# so a container never downloads one from GitHub at runtime.
FROM node:26-bookworm-slim

LABEL org.opencontainers.image.title="ROKFOSS unkernel" \
      org.opencontainers.image.source="https://github.com/KRFOSS/unkernel" \
      org.opencontainers.image.licenses="MIT AND GPL-2.0-only"

WORKDIR /opt/unkernel

# unkernel.tgz is the npm package; npm tarballs extract into `package/`.
# distros.json, alpine.erofs and debian.erofs are the images checked against
# that same distros.json by the Release workflow before it uploaded them.
COPY unkernel.tgz /tmp/unkernel.tgz
COPY distros.json alpine.erofs debian.erofs /opt/unkernel/distros/
RUN tar -xzf /tmp/unkernel.tgz -C /opt/unkernel --strip-components=1 \
 && rm -f /tmp/unkernel.tgz \
 && test -f /opt/unkernel/dist/cli.mjs \
 && test -s /opt/unkernel/dist/unkernel.wasm \
 && test -s /opt/unkernel/distros/distros.json

# --data writes here; mount a volume on /data to keep guest changes.
RUN mkdir -p /data /tmp/unkernel-cache
ENV UNKERNEL_CACHE_DIR=/tmp/unkernel-cache
WORKDIR /data

ENTRYPOINT ["node", "/opt/unkernel/dist/cli.mjs"]
CMD ["--distro", "/opt/unkernel/distros/alpine.erofs"]
