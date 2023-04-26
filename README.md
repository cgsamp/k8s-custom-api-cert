# Connect to Kubernetes API Securely with Custom Certificate

This repository shows how to use [**Contour**](https://projectcontour.io/) to allow a remote client to connect to a Kubernetes cluster's Kube API using a third-party TLS certificate that can be validated against an external Certificate Authority.

## Dependencies and assumptions

This repo uses 
- Tanzu with vSphere 7.0.3, TKGs
- AVI for Level 4 Load Balancing
- Linux or linux-like environment

 Other Kubernetes distributions and load balancers could be used.

## Using this repository

Helper tooling is provided to manage TKGs. 

### Edit this project's secrets

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

# vSphere Lab setup

## vSphere

Provision or obtain an environment with vSphere with Tanzu (the author used a VMware internal H2O lab) and a load balancer -- NSX-T, NSX Advanced Load Balancer and HAProxy are suggested in the documentation.
[vSphere with Tanzu documentation.](https://docs.vmware.com/en/VMware-vSphere/7.0/vmware-vsphere-with-tanzu/GUID-152BE7D2-E227-4DAA-B527-557B564D9718.html)

## Create a vSphere Namespace

For instance, kube-api-lab.

[Documentation.](https://docs.vmware.com/en/VMware-vSphere/7.0/vmware-vsphere-with-tanzu/GUID-1544C9FE-0B23-434E-B823-C59EFC2F7309.html)

Specifically, Storage and VM Types are required.

## Connect and Create Workload Cluster

Execute the helper script, which uses `vsphere-secrets.json` to marshall variables and connect to vSphere, returning an authenticated user to your local `kubeconfig`.

```
.tkgs/sup_connect.sh
```

## Create a TKGs Workload Cluster

See the example file `tkgs-workload-cluster-1.yaml`. This creates a basic TKGs workload cluster using three control plane notes of type `guaranteed-medium` and three worker nodes of type `best-effort-large`.

```
kubectl config use-context h2o-lab
kubectl apply -f tkgs/tkgs-workload-cluster-1.yaml
```

This will take 10 or so minutes to complete. You may watch progress with a command like this:
```
watch kubectl get tkc/tkgs-workload-cluster-1.yaml
```

Log in to the Workload Cluster.
```
tkgs/tkgs_connect.sh
```

Some additional configuration of user rights is required to allow creation of pods in the newly created cluster. A helper script is provided. We also create the Contour namespace in advance so we can install it properly.
```
.tkgs/tkgs-config.sh

```

## Other Kubernetes distributions

Required is a working cluster with rights to create namespaces and other services.

# Create PKI requirements

## Obtain certificate and private key

For this exercise, you will need a suitable TLS Certificate and associated Private Key. The author used one created by LetsEncrypt. See your corporate security team.

### LetsEncrypt

LetsEncrypt provided a wildcard certificate in the form of `pem` files. A wildcard certificate is not required if the specific domain in known.

The `pem`s may be converted to the needed base64-encoded key and cert files with these commands:
```
openssl pkey -in privkey.pem -out cert.key
openssl crl2pkcs7 -nocrl -certfile fullchain.pem | openssl pkcs7 -print_certs -out fullchain.crt
base64 -i fullchain.crt -o fullchain.crt.base64
base64 -i cert.key -o cert.key.base64
```

## Create Kubernetes secret

Use your provided certificate and private key and create the secret. Example yaml provided.

```
apiVersion: v1
kind: Secret
metadata:
  name: tls-certificate-secret
data:
  tls.crt: [Base64-encoded certificate]
  tls.key: [Base64-encoded private key]
type: kubernetes.io/tls
```

```
kubectl apply -f secrets/tls-certificate-secret.yaml
```


# Install and Deploy Contour

There are a couple of methods to deploy Contour. One is to just deploy it from upstream:
```
kubectl apply -f https://projectcontour.io/quickstart/contour.yaml
```

## Get Ingress IP

Contour creates an `envoy` service to accept inbound connections and route them. Discover the EXTERNAL-IP:

```
kubectl get service/envoy -n projectcontour
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

This tells Contour to create an Ingress of type HTTPProxy. Inbound traffic from the *virtual host* specified is served via TLS using the secret provided. For the route, the HTTPProxy connects to service kubernetes on port 443, using the tls protocol. Note that the service name `kubernetes` is mapping to the service of the same name in the default namespace, that proxies the control plane's IP set. This way, the system works without knowing the control plane IPs or having to maintain changes.

Contour is terminating the inbound TLS, and then re-encrypting with the cluster's certificate. In this configuration it does not validate the certificate's CA, but it could do so.

## Create DNS Entry

Map the envoy EXTNERAL-IP to the domain in your dns management software. Note that the domain name must match the domain name in the certificate, and specified in the HTTPProxy field `spec.virtualhost.fqdn`.

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
    server: https://k8s.yourdomain.com
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
    token: REDACTED

```

The external user may test the connection with
```
kubectl --kubeconfig=remote-kubeconfig.yaml get nodes
```

# Troubleshooting

## `curl` is a good resource to check the connections.

### Check that the Contour service is listening:
```
curl -k https://EXTERNAL-IP
```
Should return a Kubernetes "user not authorized" json object.

### Check that DNS is set up correctly.
```
ping k8s.yourdomain.com
```
Should return EXTERNAL-IP.

### Check that Contour is routing correctly
```
curl -k https://k8s.yourdomain.com
```
Should return a Kubernetes "user not authorized" json object.

### Connect that the certificate chain is set up correctly
```
curl https://k8s.yourdomain.com
```
Should return a Kubernetes "user not authorized" json object.

If there are other errors, review the verbose interaction of curl:

```
curl -v https://k8s.yourdomain.com
```

## `kubectl` issues

If you are able to connect to the domain via curl, without `-k`, and see the access-denied message, `kubectl` should also connect. If not, 
- Make sure the user is still authorized - some tokens expire after hours or days. 
- Make sure the encoding is correct. 
- Change the `cluster.cluster.server` value to the ip address.
- Add the `insecure-skip-tls-verify: true` valuye to `clusters.cluster`

