set -x

export H2O_LABNAME=$(cat secrets/vsphere_secrets.json| jq -r ."h2oLabName")
export KUBECTL_VSPHERE_PASSWORD=$(cat secrets/vsphere_secrets.json| jq -r ."vspherePassword")
export SUPERVISOR_CONTROL_PLANE_IP_ADDRESS=$(dig +short vc01cl01-wcp.$H2O_LABNAME.h2o.vmware.com)
echo The Supervisor Cluster Control Plane IP is $SUPERVISOR_CONTROL_PLANE_IP_ADDRESS

kubectl vsphere login --server=$SUPERVISOR_CONTROL_PLANE_IP_ADDRESS \
--tanzu-kubernetes-cluster-name tkgs-workload-cluster-1 \
--tanzu-kubernetes-cluster-namespace h2o-lab \
--vsphere-username administrator@vsphere.local


