# Manage multiple Kubernetes clusters with Argo CD
**Before starting this lab ensure you've completed all below sections: ** 
- [Prerequisites](./0-prerequisites.md).
- [Bootstrap AWS cluster](./1-bootstrap-aws-cluster.md).
- [Convert to self-hosted cluster](./docs/2-self-hosted-cluster.md)

This lab assumes you have a self-hosted Kubernetes cluster running on a cloud provider (AWS, Azure, GCP,...). If you haven't set this up yet, please follow the instructions in the [Convert to self-hosted cluster](./docs/2-self-hosted-cluster.md) guide.

## Install Helm addons on self-hosted cluster
Install these following Helm charts on your self-hosted cluster using `helm-init.sh` script:
- Argo CD
- Ingress NGINX Controller
- Cert Manager (Already installed when provisioning cluster)

```bash
cd gitops/bootstrap
./helm-init.sh
```

Output:
```bash
==> Adding Helm repos
==> Updating Helm repos
Hang tight while we grab the latest from your chart repositories...
...Successfully got an update from the "ingress-nginx" chart repository
...Successfully got an update from the "argo" chart repository
Update Complete. ⎈ Happy Helming!⎈
==> Installing/Upgrading ingress-nginx
Release "ingress-nginx" does not exist. Installing it now.
NAME: ingress-nginx
LAST DEPLOYED: Sun Nov  2 00:44:46 2025
NAMESPACE: ingress-nginx
STATUS: deployed
REVISION: 1
TEST SUITE: None
NOTES:
The ingress-nginx controller has been installed.
It may take a few minutes for the load balancer IP to be available.
...
==> Installing/Upgrading Argo CD
Release "argocd" has been upgraded. Happy Helming!
NAME: argocd
LAST DEPLOYED: Sun Nov  2 00:45:57 2025
NAMESPACE: argocd
STATUS: deployed
REVISION: 2
TEST SUITE: None
NOTES:
In order to access the server UI you have the following options:
...
(You should delete the initial secret afterwards as suggested by the Getting Started Guide: https://argo-cd.readthedocs.io/en/stable/getting_started/#4-login-using-the-cli)
==> Helm addons installation done
```

Check installed addons:
```bash
kubectl get pods -n ingress-nginx
kubectl get pods -n argocd
```

Output:
```bash
[h10h-aws-cluster-admin@h10h-aws-cluster|default] ➜  gitops git:(main) ✗ kubectl get pods -n ingress-nginx
NAME                             READY   STATUS    RESTARTS   AGE
ingress-nginx-controller-ppc4f   1/1     Running   0          62m
ingress-nginx-controller-zb82m   1/1     Running   0          62m
[h10h-aws-cluster-admin@h10h-aws-cluster|default] ➜  gitops git:(main) ✗ kubectl get pods -n argocd
NAME                                                READY   STATUS    RESTARTS   AGE
argocd-application-controller-0                     1/1     Running   0          15h
argocd-applicationset-controller-7dddb574cd-7phxs   1/1     Running   0          15h
argocd-dex-server-6866975d5f-vtzhw                  1/1     Running   0          15h
argocd-notifications-controller-9489d8ff4-5p6tr     1/1     Running   0          15h
argocd-redis-6f54f4677f-wlpjr                       1/1     Running   0          15h
argocd-repo-server-5dbf5b64b-2pk4s                  1/1     Running   0          15h
argocd-server-d6bc98467-rzvbb                       1/1     Running   0          15h
```


## Expose Argo CD server via Ingress
Get external IP of Ingress NGINX controller:
```bash
kubectl get svc -n ingress-nginx
```

Output:
```bash
[h10h-aws-cluster-admin@h10h-aws-cluster|default] ➜  gitops git:(main) ✗ kubectl get svc -n ingress-nginx
NAME                                 TYPE           CLUSTER-IP      EXTERNAL-IP                                                                     PORT(S)                      AGE
ingress-nginx-controller             LoadBalancer   10.105.200.55   ae42deccc1ea84baba01403d05ed6ba3-2bbf299a2e8deeac.elb.us-west-2.amazonaws.com   80:31743/TCP,443:31199/TCP   64m
ingress-nginx-controller-admission   ClusterIP      10.103.216.14   <none>                                                                          443/TCP                      64m
```

Add the EXTERNAL-IP as a CNAME record for `argocd.<your-domain>` in your DNS provider.
```text
CNAME  argocd.<your-domain>  ae42deccc1ea84baba01403d05ed6ba3-2bbf299a2e8deeac.elb.us-west-2.amazonaws.com
```

Create an Ingress resource for Argo CD:
```bash
# Create Cert Manager Issuer
kubectl apply -f gitops/manifests/cert-manager/cluster-issuer.yaml
# Create Argo CD Ingress
kubectl apply -f gitops/manifests/argocd/argocd-ingress.yaml
```

Check Ingress and Certificate resources:
```bash
[h10h-aws-cluster-admin@h10h-aws-cluster|default] ➜  gitops git:(main) ✗ kubectl get ingress -n argocd
NAME                    CLASS            HOSTS                      ADDRESS                                                                         PORTS     AGE
argocd-server-ingress   external-nginx   argocd.high10hunter.live   ae42deccc1ea84baba01403d05ed6ba3-2bbf299a2e8deeac.elb.us-west-2.amazonaws.com   80, 443   44m
[h10h-aws-cluster-admin@h10h-aws-cluster|default] ➜  gitops git:(main) ✗ kubectl get certificates -n argocd
NAME                READY   SECRET              AGE
argocd-server-tls   True    argocd-server-tls   44m
```

Access Argo CD UI at `https://argocd.<your-domain>` (e.g., `https://argocd.high10hunter.live`) to verify it's working. The default username is `admin` | password is `123456Abc#`

## Create new workload cluster using existing cloud infrastructure (BYOAI workload cluster)
### 1) Apply YAML manifest directly to self-hosted cluster
Create a new workload cluster using existing AWS infrastructure (VPC, subnets, NAT Gateway, ...). You can modify the values of vpc, subnets, and other parameters in the `clusters/aws/capa-byoai.yaml` file as per your existing setup.
```bash
# Use the self-hosted cluster context
kubie ctx h10h-aws-cluster-admin@h10h-aws-cluster

# Apply the configmaps so that the BYOAI workload cluster can use them with ClusterResourceSet
kubectl apply -f clusters/aws/confimaps 

# Apply the workload cluster manifest using existing cloud infrastructure
kubectl apply -f clusters/aws/capa-byoai.yaml
```

Check the creation status of the BYOAI workload cluster:
```bash
clusterctl describe cluster h10h-byoai-cluster # you can change the cluster name if needed
```

Output:
```bash
[h10h-aws-cluster-admin@h10h-aws-cluster|default] ➜  cloud-agnostic git:(main) ✗ clusterctl describe cluster h10h-byoai-cluster

NAME                                                           REPLICAS  AVAILABLE  READY  UP TO DATE  STATUS           REASON            SINCE  MESSAGE             
Cluster/h10h-byoai-cluster                                     3/3       3          3      3           Available: True  Available         15m                        
├─ClusterInfrastructure - AWSCluster/h10h-byoai-cluster-sqk6h                                          Ready: True      NoReasonReported  18m                        
├─ControlPlane - KubeadmControlPlane/h10h-byoai-cluster-x44bl  1/1       1          1      1                                                                         
│ └─Machine/h10h-byoai-cluster-x44bl-zj5l5                     1         1          1      1           Ready: True      Ready             15m                        
└─Workers                                                                                                                                                            
  └─MachineDeployment/h10h-byoai-cluster-worker-node-dtr6q     2/2       2          2      2           Available: True  Available         15m                        
    └─2 Machines...                                                      2          2      2           Ready: True      Ready             15m    See h10h-byoai-cluster-worker-node-dtr6q-6vq8q-t52gj, h10h-byoai-cluster-worker-node-dtr6q-6vq8q-wbqd5
```


Connect to the BYOAI workload cluster:
```bash
clusterctl get kubeconfig h10h-byoai-cluster > ~/.kube/h10h-byoai-cluster.kubeconfig
kubie ctx h10h-byoai-cluster-admin@h10h-byoai-cluster 
kubectl get no
```

Output:
```bash
[h10h-byoai-cluster-admin@h10h-byoai-cluster|default] ➜  cloud-agnostic git:(main) ✗ kubectl get no
NAME                                           STATUS   ROLES           AGE   VERSION
ip-192-168-26-219.us-west-2.compute.internal   Ready    <none>          18m   v1.32.0
ip-192-168-26-35.us-west-2.compute.internal    Ready    control-plane   19m   v1.32.0
ip-192-168-30-124.us-west-2.compute.internal   Ready    <none>          18m   v1.32.0
```

Check whether the self-hosted cluster can manage the BYOAI workload cluster:
```bash
kubie ctx h10h-aws-cluster-admin@h10h-aws-cluster
kubectl get clusters
```

Output:
```bash
[h10h-aws-cluster-admin@h10h-aws-cluster|default] ➜  cloud-agnostic git:(main) ✗ kubectl get clusters
NAME                 CLUSTERCLASS      AVAILABLE   CP DESIRED   CP AVAILABLE   CP UP-TO-DATE   W DESIRED   W AVAILABLE   W UP-TO-DATE   PHASE         AGE   VERSION
h10h-aws-cluster     aws-quick-start   True       1            1              1               2           2             2              Provisioned   42h   v1.32.0
h10h-byoai-cluster   aws-quick-start   True        1            1              1               2           2             2              Provisioned   23m   v1.32.0
```

### 2) Use GitOps to manage BYOAI workload cluster with Argo CD
Create a new workload cluster using existing AWS infrastructure (VPC, subnets, NAT Gateway, ...). You can modify the values of vpc, subnets, and other parameters in the `gitops/manifests/clusters/capa-byoai/capa-byoai.yaml` file as per your existing setup.
```bash
# Use the self-hosted cluster context
kubie ctx h10h-aws-cluster-admin@h10h-aws-cluster

# Apply the configmaps as platform addons so that the BYOAI workload cluster can use them with ClusterResourceSet
kubectl apply -f gitops/cluster-app/platform-addons.yaml

# Apply the workload cluster manifest using existing cloud infrastructure
kubectl apply -f gitops/cluster-app/capa-byoai-app.yaml 
```

The cluster creation status can be checked like in the creation via YAML manifest section above.

## Add remote BYOAI workload cluster to Argo CD
Use the Argo CD CLI to add the BYOAI workload cluster to Argo CD:
```bash
# Authenticate Argo CD CLI
argocd login --insecure --grpc-web --username admin --password=123456Abc# argocd.high10hunter.live

# Add remote BYOAI workload cluster to Argo CD
argocd cluster add h10h-byoai-cluster-admin@h10h-byoai-cluster --yes --kubeconfig ~/.kube/h10h-byoai-cluster.kubeconfig --name capa-byoai

# List clusters managed by Argo CD
argocd cluster list
```

Output:
```bash
{"level":"info","msg":"ServiceAccount \"argocd-manager\" created in namespace \"kube-system\"","time":"2025-11-07T05:50:59+07:00"}
{"level":"info","msg":"ClusterRole \"argocd-manager-role\" created","time":"2025-11-07T05:50:59+07:00"}
{"level":"info","msg":"ClusterRoleBinding \"argocd-manager-role-binding\" created","time":"2025-11-07T05:50:59+07:00"}
{"level":"info","msg":"Created bearer token secret \"argocd-manager-long-lived-token\" for ServiceAccount \"argocd-manager\"","time":"2025-11-07T05:50:59+07:00"}
Cluster 'https://h10h-byoai-apiserver-lb-c7108670128e571a.elb.us-west-2.amazonaws.com:6443' added

[h10h-aws-cluster-admin@h10h-aws-cluster|default] ➜  cloud-agnostic git:(main) ✗ argocd cluster list
SERVER                                                                             NAME        VERSION  STATUS      MESSAGE                                                  PROJECT
https://h10h-byoai-apiserver-lb-c7108670128e571a.elb.us-west-2.amazonaws.com:6443  capa-byoai           Unknown     Cluster has no applications and is not being monitored.
https://kubernetes.default.svc                                                     in-cluster  1.32     Successful
```

## Deploy applications to BYOAI workload cluster using Argo CD
```bash
# Use the self-hosted cluster context
kubie ctx h10h-aws-cluster-admin@h10h-aws-cluster

# Apply the workload cluster manifest using existing cloud infrastructure
kubectl apply -f gitops/sample-apps/appset.yaml 

# Check application status 
kubectl get applications -n argocd
```

Output:
```bash
[h10h-aws-cluster-admin@h10h-aws-cluster|default] ➜  cloud-agnostic git:(main) ✗ kubectl get application -A
NAMESPACE   NAME              SYNC STATUS   HEALTH STATUS
argocd      capa-byoai        Synced        Healthy
argocd      simple-go-dev     Synced        Healthy
argocd      simple-go-prod    Synced        Healthy
argocd      simple-go-stage   Synced        Healthy
```

## Clean up 
Remove the BYOAI workload cluster from Argo CD:
```bash
argocd cluster rm capa-byoai --yes
```
