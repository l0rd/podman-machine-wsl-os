#!/usr/bin/env bash
#
# This script builds a version of the WSL image with the development version of podman (main branch)
# It gets podman from the fedora copr repository `rhcontainerbot/podman-next`:
# https://copr.fedorainfracloud.org/coprs/rhcontainerbot/podman-next
# https://copr.fedorainfracloud.org/coprs/rhcontainerbot/podman-next/package/podman/
#
# FIXME: Currently only work on Linux and only builds an amd64 image

set -eou pipefail

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

FEDORA_IMAGE_TAG=40 
PACKAGE_LIST="procps-ng openssh-server net-tools iproute dhcp-client crun-wasm wasmedge-rt qemu-user-static subscription-manager gvisor-tap-vsock-gvforwarder" 
VER_PFX="5.3"
BUILD_ARCH="amd64"
ROOTFS_FILE=$VER_PFX-rootfs-$BUILD_ARCH.tar.zst
IMAGE_REGISTRY="quay.io"
IMAGE_REPO="mloriedo"
IMAGE_NAME="machine-os-wsl"
IMAGE_TAG="5.3-next"

podman image pull docker.io/library/fedora:$FEDORA_IMAGE_TAG
podman create -v "$SCRIPT_DIR":/mnt:Z --name fedora-update docker.io/library/fedora:$FEDORA_IMAGE_TAG sleep 7200
podman start fedora-update
podman exec -it fedora-update sh -c "sudo cp /mnt/rhcontainerbot-podman-next-fedora.repo /etc/yum.repos.d/"
podman exec -it fedora-update sh -c "sudo cp /mnt/rhcontainerbot-podman-next-fedora.gpg /etc/pki/rpm-gpg/"
podman exec -it fedora-update sh -c "dnf update -y && dnf -y install podman podman-docker $PACKAGE_LIST && dnf clean all && rm -rf /var/cache/yum"

echo "Creating rootfs.tar from container..."
podman export --output $SCRIPT_DIR/rootfs.tar fedora-update
podman rm -f fedora-update

# GNu tar has a corruption bugs with --delete, so use bsdtar to filter instead
echo "Filtering rootfs.tar using container..."
podman run -v "$SCRIPT_DIR":/mnt --security-opt label=disable fedora sh -c 'dnf -y install bsdtar && bsdtar -cf /mnt/new.tar --exclude etc/resolv.conf @/mnt/rootfs.tar'
mv $SCRIPT_DIR/new.tar $SCRIPT_DIR/rootfs.tar
mkdir -p $SCRIPT_DIR/etc; touch $SCRIPT_DIR/etc/resolv.conf
tar rf $SCRIPT_DIR/rootfs.tar --mode=644 --group=root --owner=root $SCRIPT_DIR/etc/resolv.conf
echo "Compressing rootfs.tar.."
rm $SCRIPT_DIR/rootfs.tar.zst || true
#zstd -T0 --auto-threads=logical --ultra -22 --long --rm --verbose $SCRIPT_DIR/rootfs.tar
zstd -T0 --auto-threads=logical -22 --long --rm --verbose $SCRIPT_DIR/rootfs.tar
echo "Done"
mv $SCRIPT_DIR/rootfs.tar.zst "$SCRIPT_DIR/$ROOTFS_FILE"

FULL_IMAGE_NAME=$IMAGE_REGISTRY/$IMAGE_REPO/$IMAGE_NAME:$IMAGE_TAG
podman rmi "$FULL_IMAGE_NAME" || true
buildah manifest create "$FULL_IMAGE_NAME"
disk_arch="x86_64"
arch="amd64"
buildah manifest add --artifact --artifact-type="" --os=linux --arch="$disk_arch" --annotation "disktype=wsl" "$FULL_IMAGE_NAME" "$SCRIPT_DIR/$VER_PFX-rootfs-$arch.tar.zst"

echo "Image $FULL_IMAGE_NAME has been built successfully"
