ARG BASE_IMAGE=pkg-base-debian12
FROM ${BASE_IMAGE}

# No extra dependencies needed for pkg_lib tests (base image has coreutils)

COPY files/ /opt/files/
COPY pkg/ /opt/pkg/
COPY tests/ /opt/tests/

WORKDIR /opt/tests
CMD ["bats", "--formatter", "tap", "/opt/tests/"]
