# Connect to TKGs Workload Cluster Externally with Custom Certificate

A third-party service may wish to connect to a Kubernetes workload cluster via kubeapi to conduct maintenance or security-related tasks, such as inject secrets from a remote secure store. The third party will want assurance that they are connecting to the right host, and will accomplish this via standard PKI techniques. Namely, they will be provided a TLS Server Certificate, and validate that Certificate's issuing Certificate Authority through a trusted hierarchy.

This means that the Platform Owner must configure the Control Plane Service with a securely provisioned certificate, as well as make sure the internal Kubernetes control plane components are not impacted or confused.

## Options

- Using standard Kubernetes bootstrap and certificate management, it is possible to **provide the target cluster with a trusted Certificate Authority**. However, Certificate Authorities, including intermediate CAs, are not usually available in enterprise environments. Lifecycle maintenance activities may also be impacted.
- An Operator could directly **connect to the Kubernetes Control Plane Nodes via ssh and replace certain certificates**, as described in Kubernetes documentation. This would present several maintenance challenges, including allowing the Control Plane to be accessed by other environment components that are not aware of the third party requirement.
- An **external load balancer** may be configured to provide TLS Termination from the client, using preferred certificates, and then re-encryption with the target's Certificate and Certificate Authority.
- A **secondary Kubernetes Ingress** object may be provisioned that provides secondary access to the service/control-plane. This secondary ingress will be provisioned with the selected Certificate, while other uses access the primary ingress unchanged.
- There may be other methods, as the ways to configure Kubernetes to do strange and wonderful things is limited only by the user's imagination and patience.

## This Guide

This guide will detail the **external load balancer** example, with a working example. The **secondary Kubernetes Ingress** method is in the works. 

## Dependencies and assumptions

This Guide uses Tanzu with vSphere 7.0.3, configured with NSX AVI Advanced Load Balancer. Other configurations, such as OSS Kubernetes and HAProxy, are possible, although not detailed here.

# Lab environment setup

## vSphere

Provision an environment with vSphere with Tanzu and AVI load balancer (the author used a VMware internal H2O lab).
[vSphere with Tanzu documentation.](https://docs.vmware.com/en/VMware-vSphere/7.0/vmware-vsphere-with-tanzu/GUID-152BE7D2-E227-4DAA-B527-557B564D9718.html)

## Create a vSphere Namespace

This lab used a namespace called `h2o-lab`. [Documentation.](https://docs.vmware.com/en/VMware-vSphere/7.0/vmware-vsphere-with-tanzu/GUID-177C23C4-ED81-4ADD-89A2-61654C18201B.html)

To the namespace,
- [Assign Storage](https://docs.vmware.com/en/VMware-vSphere/7.0/vmware-vsphere-with-tanzu/GUID-AB01BAEF-1AAF-44FE-8F3E-3B8E8A60B33A.html)
- [Assign VM types]()link needed.

# Test setup

For convenience, there are bash scripts that perform some of the more complicated steps. They rely on configuration in a file called `secrets/vsphere_secrets.json`. There is a file called `secrets/sample-vsphere_secrets.json` that you may copy and edit.

These are authored for a unix enviroment, such as Linux, macos, or Windows Subsystem for Linux (WSL). The machine must be on a network that can access the vSphere components.

## Log in to the TKGs Supervisor cluster

Execute the helper script. Look inside for explanatory comments.
```
./sup_connect.sh
```

## Create a TKGs Workload Cluster

See the example file `tkgs-workload-cluster-1.yaml`. This creates a basic TKGs workload cluster using three control plane notes of type `guaranteed-medium` and three worker nodes of type `best-effort-large`.

```
kubectl config use-context h2o-lab
kubectl apply -f tkgs-workload-cluster-1.yaml
```

This will take 10 or so minutes to complete. You may watch progress with a command like this:
```
watch kubectl get tkc/tkgs-workload-cluster-1.yaml
```

### Optional: Test TKGs Cluster

Log in to the Workload Cluster.
```
tkgs_connect.sh
```

Deploy and test a `nginx` workload. Some additional configuration of user rights is required to allow creation of pods in the newly created cluster. A helper script is provided.
```
./tkgs-config.sh
```

# Create External Load Balancer

For this exercise, you will need a suitable TLS Certificate and associated Private Key. The author used one created by LetsEncrypt. See your corporate security team.

Navigate to the Applications / Virtual Services page. Notice the services that TKGs has created within Avi. This guide will add a new one.

![Screenshot](doc_images/virtual-services-overview.png "Screenshot")

First we must create some dependent objects.

## SSL/TLS Certificates

Navigate to `Templates / Security / SSL/TLS Certificates`. Choose `CREATE / Application Certificate`. 

- Type: Import
- Import certificate file
- Import private key

![Screenshot](doc_images/edit-certificate.png "Screenshot")

## Pool

Create a server pool to receive traffic. The TKGs Workload Cluster Certificate Authority (Randomly generated) will be required.

It may be obtained by running
```
kubectl config view --flatten --output=json | jq -r '.clusters[] | select(.name=="[NAME OF CLUSTER]") | .cluster."certificate-authority-data"' > tkgs_ca.cert
```
(SCREENSHOT AND DETAILS COMING)

## Virtual Service

Click on CREATE VIRTUAL SERVICE and choose Advanced Setup. Values are as follows:

Name: tkgs-kubeapi
(TODO)

## DNS

Find the IP provided by the Virtual Service and create a DNS A record, such as `k8s-api`.

# Configure Third Party Client

The external party will need a user token. It will NOT need a certificate authority, as the client will verify the Certificate with it's own Certificate Authority trust chain.

Here is an example kubeconfig file:
```
apiVersion: v1
clusters:
- cluster:
    server: https://k8s-worker.csamp-tanzu.com
  name: remote-tkgs-workload-cluster-1
contexts:
- context:
    cluster: remote-tkgs-workload-cluster-1
    user: third-party
  name: remote-tkgs-workload-cluster-1
current-context: remote-tkgs-workload-cluster-1
kind: Config
preferences: {}
users:
- name: third-party
  user:
    token: ey...REDACTED

```

The external user may test the connection with
```
kubectl --kubeconfig=csamp-tanzu-kubeconfig.yaml get nodes
```
