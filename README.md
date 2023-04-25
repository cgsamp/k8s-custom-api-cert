# Connect to TKGs Workload Cluster Externally with Custom Certificate

## This Guide

This guide will detail the **Contour Ingress** method of providing secure connections to the TKG Workload Cluster's Kubeapi.

## Dependencies and assumptions

This Guide uses Tanzu with vSphere 7.0.3 with AVI for Level 4 Load Balancing. Other load balancers could be used.

# Lab environment setup

## vSphere

Provision an environment with vSphere with Tanzu and AVI load balancer (the author used a VMware internal H2O lab).
[vSphere with Tanzu documentation.](https://docs.vmware.com/en/VMware-vSphere/7.0/vmware-vsphere-with-tanzu/GUID-152BE7D2-E227-4DAA-B527-557B564D9718.html)

## Create a vSphere Namespace

This lab used a namespace called `h2o-lab`. [Documentation.](https://docs.vmware.com/en/VMware-vSphere/7.0/vmware-vsphere-with-tanzu/GUID-177C23C4-ED81-4ADD-89A2-61654C18201B.html)

To the namespace,
- [Assign Storage](https://docs.vmware.com/en/VMware-vSphere/7.0/vmware-vsphere-with-tanzu/GUID-AB01BAEF-1AAF-44FE-8F3E-3B8E8A60B33A.html)
- [Assign VM types]()link needed.

## Edit this project's secrets

For convenience, there are bash scripts that perform some of the more complicated steps. They rely on configuration in a file called `secrets/vsphere_secrets.json`. There is a file called `secrets/sample-vsphere_secrets.json` that you may copy and edit.

```
{
    "vsphereWcpServername": "FQDN like: vc01cl01-wcp.h2o-4-10063.h2o.vmware.com", 
    "vsphereUsername": "administrator@vsphere.local",
    "vspherePassword": "",
    "supervisorNamespace": "as created in vSphere workload management",
    "tanzuWorkloadClusterName": "name of the workload cluster"
}
```

These are authored for a unix enviroment, such as Linux, macos, or Windows Subsystem for Linux (WSL). The machine must be on a network that can access the vSphere components.

# Connect and Create Workload Cluster

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

Log in to the Workload Cluster.
```
tkgs_connect.sh
```

Some additional configuration of user rights is required to allow creation of pods in the newly created cluster. A helper script is provided. We also create the Contour namespace in advance so we can install it properly.
```
./tkgs-config.sh

```


# Create PKI requirements

## Obtain certificate and private key

For this exercise, you will need a suitable TLS Certificate and associated Private Key. The author used one created by LetsEncrypt. See your corporate security team.

## DNS

Find the IP provided by the Virtual Service and create a DNS A record, such as `k8s-api`.

## Create Kubernetes secret

Use your provided certificate and private key and create the secret. Example yaml provided.

```
apiVersion: v1
kind: Secret
metadata:
  name: k8s-api-tls-certificate
data:
  tls.crt: [Base64-encoded certificate]
  tls.key: [Base64-encoded private key]
type: kubernetes.io/tls
```

```
kubectl apply -f secrets/tls-certificate-secret.yaml
```

### NOTE on cert formats

When the author used LetsEncrypt, *pem* formatted files were provided. To get the values above, the pem were converted to crt, then encoded.

```
openssl pkey -in privkey.pem -out cert.key
openssl crl2pkcs7 -nocrl -certfile fullchain.pem | openssl pkcs7 -print_certs -out fullchain.crt
base64 -i fullchain.crt -o fullchain.crt.base64
base64 -i cert.key -o cert.key.base64
```


# Install and Deploy Contour

There are a couple of methods to deploy Contour. One is to just deploy it from upstream:
```
kubectl apply -f https://projectcontour.io/quickstart/contour.yaml
```

Now deploy the specific Contour CRD:
```
kind: HTTPProxy
apiVersion: projectcontour.io/v1
metadata:
  name: kubeapi-proxy
  namespace: default
spec:
  virtualhost:
    fqdn: k8s-api.yourdomain.com
    tls:
      secretName: tls-certificate-secret
  routes:
    - services:
        - name: kubernetes
          port: 443
          protocol: tls

```

This tells Contour to create an Ingress of type HTTPProxy. Inbound traffic from the *virtual host* specified is served via TLS using the secret provided. For the route, the HTTPProxy connects to service kubernetes on port 443, using the tls protocol.

Contour is terminating the inbound TLS, and then re-encrypting.


# Configure Third Party Client

The external party will need a user token. It will NOT need a certificate authority, as the client will verify the Certificate with it's own Certificate Authority trust chain.

Get the user token from an existing authorized user, like so:
```
 kubectl config view --flatten --minify -o json | jq -r '.users[] | select(.name=="--your-username--") | .user.token'
 ```


Here is an example kubeconfig file:
```
apiVersion: v1
clusters:
- cluster:
    server: https://k8s.csamp-tanzu.com
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
kubectl --kubeconfig=remote-kubeconfig.yaml get nodes
```
