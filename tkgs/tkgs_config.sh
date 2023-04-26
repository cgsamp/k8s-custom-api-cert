#!/bin/bash
kubectl config use-context tkgs-workload-cluster-1
kubectl create namespace projectcontour
kubectl create rolebinding rolebinding-default-privileged-sa-ns_default --namespace=default --clusterrole=psp:vmware-system-privileged --group=system:serviceaccounts
kubectl create rolebinding rolebinding-default-privileged-sa-ns_default --namespace=projectcontour --clusterrole=psp:vmware-system-privileged --group=system:serviceaccounts
