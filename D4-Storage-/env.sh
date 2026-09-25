# D4 storage lab - the two site-specific values ex03 and ex04 need.
#
# Source it, don't run it:
#
#     source env.sh
#
# Both default to auto-detected values and both can be overridden by
# exporting them beforehand, e.g. if the NFS server is not this node:
#
#     NFS_SERVER=10.0.0.5 source env.sh

# The address Pods (really: the kubelet, and the CSI driver) reach the NFS
# server on. Defaults to this node's first non-loopback IPv4 address.
export NFS_SERVER="${NFS_SERVER:-$(hostname -I | awk '{print $1}')}"

# The CIDR the NFS export is opened to. This must cover the NODE's own IP,
# not just the Pod CIDR: the in-tree NFS volume plugin has the kubelet do
# the mount, so a Pod-CIDR-only export fails with "access denied by server".
# Defaults to a /24 around this node.
export NODE_SUBNET="${NODE_SUBNET:-$(echo "${NFS_SERVER}" | awk -F. '{print $1"."$2"."$3".0/24"}')}"

# The exported directory. ex03 mounts it directly; ex04's CSI driver creates
# one subdirectory per PVC underneath it.
export NFS_EXPORT_DIR="${NFS_EXPORT_DIR:-/srv/nfs/k3s-training}"

echo "NFS_SERVER=${NFS_SERVER}"
echo "NODE_SUBNET=${NODE_SUBNET}"
echo "NFS_EXPORT_DIR=${NFS_EXPORT_DIR}"
