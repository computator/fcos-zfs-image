FROM quay.io/fedora/fedora-coreos:stable AS fcos-query

RUN rpm -q kernel --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}' > /kver.txt

# podman run --rm -i quay.io/fedora/fedora-coreos:stable sh -c '. /etc/os-release && echo $VERSION_ID'
ARG MAJOR_VER
FROM registry.fedoraproject.org/fedora:${MAJOR_VER} AS build
COPY --from=fcos-query /kver.txt /kver.txt
RUN set -eux; \
	dnf install -y fedora-repos-archive https://zfsonlinux.org/fedora/zfs-release-2-5$(rpm --eval "%{dist}").noarch.rpm; \
	dnf install -y kernel-devel-$(cat /kver.txt) rpm-build \
		libaio-devel libattr-devel libblkid-devel libffi-devel libtirpc-devel \
		libudev-devel libuuid-devel ncompress python3-cffi python3-devel \
		python3-packaging python3-setuptools;
RUN set -eux; \
	dnf install -y --downloadonly --downloaddir /tmp zfs-dkms; \
	rpm -i --nodeps \
		/tmp/zfs-dkms*.rpm \
		/tmp/systemd*.rpm
ARG BUILD_JOBS=
RUN set -eux; \
	cd /usr/src/zfs-$(rpm -q zfs-dkms --queryformat '%{VERSION}'); \
	./configure --with-config=kernel --with-linux{,-obj}=/usr/src/kernels/$(cat /kver.txt); \
	make -j ${BUILD_JOBS:-$(nproc)} rpm-utils rpm-kmod; \
	rm -fv *-devel-*.rpm *-debug*.rpm zfs-test-*.rpm *.src.rpm; \
	mkdir /rpms; \
	mv *.rpm /rpms/

FROM quay.io/fedora/fedora-coreos:stable

LABEL org.opencontainers.image.source=https://github.com/computator/fcos-zfs-image

COPY --from=build /rpms/*.rpm /tmp/
RUN set -eux; \
	rpm-ostree install /tmp/*.rpm; \
	depmod -a $(rpm -q kernel --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}'); \
	echo zfs > /etc/modules-load.d/zfs.conf; \
	ostree container commit
