#!/bin/bash
export H2O_LABNAME=$(cat secrets/vsphere_secrets.json| jq -r ."h2oLabName")
export KUBECTL_VSPHERE_PASSWORD=$(cat secrets/vsphere_secrets.json| jq -r ."vspherePassword")
export KUBERNETES_CONTROL_PLANE_IP_ADDRESS=$(dig +short vc01cl01-wcp.$H2O_LABNAME.h2o.vmware.com)
echo The Supervisor Cluster Control Plane IP is $KUBERNETES_CONTROL_PLANE_IP_ADDRESS

## May need to set your own url here if not in a lab.

kubectl vsphere logout
kubectl vsphere login --server=$KUBERNETES_CONTROL_PLANE_IP_ADDRESS --vsphere-username administrator@vsphere.local