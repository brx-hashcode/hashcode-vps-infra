# Portainer with the dead html5shim <script> removed from index.html.
#
# Portainer's index.html still loads //html5shim.googlecode.com/svn/trunk/html5.js
# inside an IE<9 conditional comment. googlecode.com is dead and flagged by
# Google Safe Browsing, so Chrome marked the whole Portainer host as a
# dangerous site. Upstream: https://github.com/portainer/portainer/issues/13118
#
# Delete this image (and the `build:` in docker-compose.yml) once a Portainer
# release drops the tag.
#
# The Portainer image has no shell, so the patch is done in an alpine stage and
# copied back. The grep fails the build if the tag survives the sed, and sed
# itself fails if index.html ever moves.
ARG PORTAINER_VERSION

FROM portainer/portainer-ee:${PORTAINER_VERSION} AS upstream

FROM alpine:3.22 AS patch
COPY --from=upstream /public/index.html /index.html
RUN sed -i '/html5shim\.googlecode\.com/d' /index.html \
 && ! grep -q googlecode /index.html

FROM upstream
COPY --from=patch /index.html /public/index.html
