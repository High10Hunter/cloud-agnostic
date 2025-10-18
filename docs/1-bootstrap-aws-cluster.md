# Bootstrap AWS cluster with Cluster API
**Before starting this section ensure you've completed the [prerequisites](./0-prerequisites.md).**

## Bootstrap ephemeral management cluster 
You need to authenticate with AWS before proceeding. You can do this by setting the appropriate environment variables or using the AWS CLI to configure your credentials.

### Bootstrap ephemeral KinD cluster.
This cluster will be the temporary management cluster used to provision clusters on the AWS infrastructure.
```bash
./scripts/init-capa-bootstrap-cluster.sh
# Get access to the ephemeral KinD cluster (kubie must be installed)
kubie ctx kind-capi-bootstrap
```

Output:
```bash
No kind clusters found.
Creating ephemeral bootstrap Kind cluster 'capi-bootstrap'...
Creating cluster "capi-bootstrap" ...
 ✓ Ensuring node image (kindest/node:v1.34.0) 🖼
 ✓ Preparing nodes 📦
 ✓ Writing configuration 📜
 ✓ Starting control-plane 🕹️
 ✓ Installing CNI 🔌
 ✓ Installing StorageClass 💾
Set kubectl context to "kind-capi-bootstrap"
You can now use your cluster with:

kubectl cluster-info --context kind-capi-bootstrap

Not sure what to do next? 😅  Check out https://kind.sigs.k8s.io/docs/user/quick-start/
✅ Bootstrap cluster ready: capi-bootstrap
Checking AWS CloudFormation stack 'cluster-api-provider-aws-sigs-k8s-io' in region 'us-east-1'...
CloudFormation stack exists and is up-to-date. Attempting update (may be no-op)...
Attempting to create AWS CloudFormation stack cluster-api-provider-aws-sigs-k8s-io
...
Fetching providers
Installing cert-manager version="v1.18.2"
...
✅ Cluster API initialized with AWS provider.
```

Check the client access to KinD cluster:
```bash
kubectl get no
```

Output:
```bash
NAME                           STATUS   ROLES           AGE    VERSION
capi-bootstrap-control-plane   Ready    control-plane   111s   v1.34.0
```

If the infrastructure provider components are not yet installed, you can manually re-authenticate with the KinD management cluster then re-run the `init-capa-bootstrap-cluster.sh` script:
```bash
kubie ctx kind-capi-bootstrap
./scripts/init-capa-bootstrap-cluster.sh
```

### Provision ClusterClass for AWS infrastructure
We need to wait for the `capa-controller-manager` to be fully initialized and running before continuing with the ClusterClass provisioning.
```bash
NAMESPACE                           NAME                                                             READY   STATUS    RESTARTS   AGE
capa-system                         capa-controller-manager-66cf66d9f8-6svkx                         1/1     Running   0          9m57s
capi-kubeadm-bootstrap-system       capi-kubeadm-bootstrap-controller-manager-74854f79f5-vbvmm       1/1     Running   0          9m59s
capi-kubeadm-control-plane-system   capi-kubeadm-control-plane-controller-manager-56df8d4f54-5c2gx   1/1     Running   0          9m58s
capi-system                         capi-controller-manager-6b976d9448-hx6zg                         1/1     Running   0          9m59s
cert-manager                        cert-manager-548f7cf98c-kzvsl                                    1/1     Running   0          10m
cert-manager                        cert-manager-cainjector-8798f647f-nhf7f                          1/1     Running   0          10m
cert-manager                        cert-manager-webhook-6c8678dc46-sw4jc                            1/1     Running   0          10m
kube-system                         coredns-66bc5c9577-7tl5t                                         1/1     Running   0          10m
kube-system                         coredns-66bc5c9577-cbv98                                         1/1     Running   0          10m
kube-system                         etcd-capi-bootstrap-control-plane                                1/1     Running   0          10m
kube-system                         kindnet-n2kdm                                                    1/1     Running   0          10m
kube-system                         kube-apiserver-capi-bootstrap-control-plane                      1/1     Running   0          10m
kube-system                         kube-controller-manager-capi-bootstrap-control-plane             1/1     Running   0          10m
kube-system                         kube-proxy-7cxgc                                                 1/1     Running   0          10m
kube-system                         kube-scheduler-capi-bootstrap-control-plane                      1/1     Running   0          10m
local-path-storage                  local-path-provisioner-7b8c8ddbd6-xt6nb                          1/1     Running   0          10m
```

Then apply the ClusterClass manifest for AWS infrastructure:
```bash
kubectl apply -f clusterclass/templates/aws-clusterclass.yaml
```

Output:
```bash
clusterclass.cluster.x-k8s.io/aws-quick-start created
awsclustertemplate.infrastructure.cluster.x-k8s.io/quick-start created
kubeadmcontrolplanetemplate.controlplane.cluster.x-k8s.io/quick-start-control-plane created
awsmachinetemplate.infrastructure.cluster.x-k8s.io/quick-start-control-plane created
awsmachinetemplate.infrastructure.cluster.x-k8s.io/quick-start-worker-machinetemplate created
kubeadmconfigtemplate.bootstrap.cluster.x-k8s.io/quick-start-worker-bootstraptemplate created
```

Check the ClusterClass resources:
```bash
kubectl get clusterclass
```

Output:
```bash
NAME              VARIABLES READY   AGE
aws-quick-start   True              54s
```

### Create AWS workload cluster from ClusterClass
Before creating AWS cluster you need to create a ssh key pair in the AWS region you are using (default is `us-east-1`):
```bash
aws ec2 create-key-pair --key-name <key_pair_name> --query 'KeyMaterial' --output text > <directory>/<key_pair_name>.pem
```
In my sample `capa-quickstart.yaml` file is using the ssh key named `capa-rsa-key-pair.pem` you can change it if needed.

Create an AWS workload cluster using the previously created ClusterClass:
```bash
# 1) Apply the configmaps first
kubectl apply -f clusters/aws/configmaps
## Expected output:
# configmap/aws-ccm-addon created
# configmap/cni-calico created
# configmap/aws-ebs-csi-driver-addon created

# 2) Apply the workload cluster manifest
kubectl apply -f clusters/aws/capa-quickstart.yaml
## Expected output:
# cluster.cluster.x-k8s.io/h10h-aws-cluster created
# clusterresourceset.addons.cluster.x-k8s.io/crs-cni created
# clusterresourceset.addons.cluster.x-k8s.io/crs-ccm created
# clusterresourceset.addons.cluster.x-k8s.io/crs-csi created
```

Check the creation status of the AWS workload cluster:
```bash
clusterctl describe cluster h10h-aws-cluster # you can change the cluster name if needed
```

Output (At the provision step):
```bash
NAME                                                         REPLICAS  AVAILABLE  READY  UP TO DATE  STATUS            REASON                      SINCE  MESSAGE      
Cluster/h10h-aws-cluster                                     0/2       0          0      0           Available: False  NotAvailable                34s    * RemoteConnectionProbe: Remote connection not established yet
│                                                                                                                                                         * InfrastructureReady: 3 of 8 completed
│                                                                                                                                                         * ControlPlaneAvailable: Control plane not yet initialized
│                                                                                                                                                         * WorkersAvailable:
│                                                                                                                                                           * MachineDeployment h10h-aws-cluster-md-0-rsqf2: 0 available replicas, at least 1 required
│                                                                                                                                                             (spec.strategy.rollout.maxUnavailable is 0, spec.replicas is 1)
├─ClusterInfrastructure - AWSCluster/h10h-aws-cluster-msw9f                                          Ready: False      NatGatewaysCreationStarted  24s    3 of 8 completed
└─ControlPlane - KubeadmControlPlane/h10h-aws-cluster-ltlpn  0/1       0          0      0 
```

You can watch the bootrapping process by viewing the logs of the `capa-controller-manager` pod:
```bash
[kind-capi-bootstrap|default] ➜  cloud-agnostic git:(main) ✗ kubectl get po -n capa-system
NAME                                       READY   STATUS    RESTARTS   AGE
capa-controller-manager-66cf66d9f8-t5kzh   1/1     Running   0          3m48s

[kind-capi-bootstrap|default] ➜  cloud-agnostic git:(main) ✗ kubectl logs capa-controller-manager-66cf66d9f8-t5kzh -n capa-system
I1017 13:15:14.880098       1 logger.go:78] "feature gates: AlternativeGCStrategy=false,AutoControllerIdentityCreator=true,BootstrapFormatIgnition=false,EKS=true,EKSAllowAddRoles=false,EKSEnableIAM=false,EKSFargate=false,EventBridgeInstanceState=false,ExternalResourceGC=true,MachinePool=false,MachinePoolMachines=false,ROSA=false,TagUnmanagedNetworkResources=true\n" logger="setup"
I1017 13:15:14.880152       1 logger.go:78] "enabling external resource garbage collection" logger="setup"
I1017 13:15:14.889640       1 logger.go:78] "controller disabled" logger="setup" controller="AWSMachine" controller-group="unmanaged"
I1017 13:15:14.889673       1 logger.go:78] "AutoControllerIdentityCreator enabled" logger="setup"
I1017 13:15:14.889713       1 webhook.go:226] "Registering a validating webhook" logger="controller-runtime.builder" GVK="infrastructure.cluster.x-k8s.io/v1beta2, Kind=AWSMachineTemplate" path="/validate-infrastructure-cluster-x-k8s-io-v1beta2-awsmachinetemplate"
I1017 13:15:14.889786       1 server.go:183] "Registering webhook" logger="controller-runtime.webhook" path="/validate-infrastructure-cluster-x-k8s-io-v1beta2-awsmachinetemplate"
I1017 13:15:14.889831       1 server.go:183] "Registering webhook" logger="controller-runtime.webhook" path="/convert"
I1017 13:16:12.624046       1 warning_handler.go:65] "metadata.finalizers: \"awscluster.infrastructure.cluster.x-k8s.io\": prefer a domain-qualified finalizer name including a path (/) to avoid accidental conflicts with other finalizer writers" logger="KubeAPIWarningLogger"
...
I1017 13:16:14.863852       1 vpc.go:132] "Created VPC" controller="awscluster" controllerGroup="infrastructure.cluster.x-k8s.io" controllerKind="AWSCluster" AWSCluster="default/h10h-aws-cluster-msw9f" namespace="default" name="h10h-aws-cluster-msw9f" reconcileID="13ad0043-b06c-4569-a60e-84d3ae68e899" cluster="default/h10h-aws-cluster" vpc-id="vpc-0d6e3f7f24425cffe"
I1017 13:16:16.455221       1 subnets.go:52] "Reconciling subnets" controller="awscluster" controllerGroup="infrastructure.cluster.x-k8s.io" controllerKind="AWSCluster" AWSCluster="default/h10h-aws-cluster-msw9f" namespace="default" name="h10h-aws-cluster-msw9f" reconcileID="13ad0043-b06c-4569-a60e-84d3ae68e899" cluster="default/h10h-aws-cluster"
I1017 13:16:18.654848       1 subnets.go:521] "Created subnet" controller="awscluster" controllerGroup="infrastructure.cluster.x-k8s.io" controllerKind="AWSCluster" AWSCluster="default/h10h-aws-cluster-msw9f" namespace="default" name="h10h-aws-cluster-msw9f" reconcileID="13ad0043-b06c-4569-a60e-84d3ae68e899" cluster="default/h10h-aws-cluster" id="subnet-0c1ff581b4cce1be3" public=true az="us-east-1a" cidr="192.168.0.0/20" ipv6=false ipv6-cidr=""
I1017 13:16:20.622007       1 subnets.go:521] "Created subnet" controller="awscluster" controllerGroup="infrastructure.cluster.x-k8s.io" controllerKind="AWSCluster" AWSCluster="default/h10h-aws-cluster-msw9f" namespace="default" name="h10h-aws-cluster-msw9f" reconcileID="13ad0043-b06c-4569-a60e-84d3ae68e899" cluster="default/h10h-aws-cluster" id="subnet-06fe816867c903477" public=false az="us-east-1a" cidr="192.168.16.0/20" ipv6=false ipv6-cidr=""
I1017 13:16:21.880466       1 gateways.go:135] "Created Internet gateway for VPC" controller="awscluster" controllerGroup="infrastructure.cluster.x-k8s.io" controllerKind="AWSCluster" AWSCluster="default/h10h-aws-cluster-msw9f" namespace="default" name="h10h-aws-cluster-msw9f" reconcileID="13ad0043-b06c-4569-a60e-84d3ae68e899" cluster="default/h10h-aws-cluster" internet-gateway-id="igw-00a4054ddde6c40b3" vpc-id="vpc-0d6e3f7f24425cffe"
```

Output (When the cluster is ready):
```bash
[kind-capi-bootstrap|default] ➜  cloud-agnostic git:(main) ✗ clusterctl describe cluster h10h-aws-cluster

NAME                                                         REPLICAS  AVAILABLE  READY  UP TO DATE  STATUS           REASON            SINCE  MESSAGE
Cluster/h10h-aws-cluster                                     2/2       2          2      2           Available: True  Available         95s
├─ClusterInfrastructure - AWSCluster/h10h-aws-cluster-tpkr2                                          Ready: True      NoReasonReported  4m29s
├─ControlPlane - KubeadmControlPlane/h10h-aws-cluster-9sx9t  1/1       1          1      1
│ └─Machine/h10h-aws-cluster-9sx9t-mwnxd                     1         1          1      1           Ready: True      Ready             112s
└─Workers
  └─MachineDeployment/h10h-aws-cluster-md-0-t5x84            1/1       1          1      1           Available: True  Available         95s
    └─Machine/h10h-aws-cluster-md-0-t5x84-wgdlk-h4jhr        1         1          1      1           Ready: True      Ready             96s

```

Connect to the AWS workload cluster:
```bash
clusterctl get kubeconfig h10h-aws-cluster > ~/.kube/h10h-aws-cluster.kubeconfig
kubie ctx h10h-aws-cluster-admin@h10h-aws-cluster 
kubectl get no
```

Output:
```bash
[h10h-aws-cluster-admin@h10h-aws-cluster|default] ➜  cloud-agnostic git:(main) ✗ kubectl get no
NAME                             STATUS   ROLES           AGE   VERSION
ip-192-168-19-220.ec2.internal   Ready    <none>          10m   v1.32.0
ip-192-168-31-133.ec2.internal   Ready    control-plane   12m   v1.32.0
```

## Validate AWS cluster addons (CNI, CCM, CSI)
Connected to the AWS workload cluster, check the addons pods:
### 1) AWS Cloud Controller Manager (aws-ccm)
Things to verify:
- CCM pods are healthy
- Nodes have .spec.providerID set (aws:///…)
- A Service type=LoadBalancer gets an AWS NLB hostname and is reachable

```bash
# Controller daemonset
kubectl -n kube-system get ds | egrep -i 'aws|cloud'
kubectl get nodes -o custom-columns=NAME:.metadata.name,PROVIDERID:.spec.providerID,TAINTS:.spec.taints
```

Output:
```bash
[h10h-aws-cluster-admin@h10h-aws-cluster|default] ➜  cloud-agnostic git:(main) ✗ kubectl -n kube-system get ds | egrep -i 'aws|cloud'
kubectl get nodes -o custom-columns=NAME:.metadata.name,PROVIDERID:.spec.providerID,TAINTS:.spec.taints

aws-cloud-controller-manager   1         1         1       1            1           node-role.kubernetes.io/control-plane=   32m
NAME                             PROVIDERID                              TAINTS
ip-192-168-28-111.ec2.internal   aws:///us-east-1a/i-089fc8dfda9891084   [map[effect:NoSchedule key:node-role.kubernetes.io/control-plane]]
ip-192-168-30-212.ec2.internal   aws:///us-east-1a/i-0606ce12fb0353bc6   <none>
```

The `PROVIDERID` field indicates that the nodes are running on AWS infrastructure.
Create resources to test the CCM functionality:
```bash
kubectl apply -f clusters/aws/tests/aws-ccm-validate.yaml 
# Wait until EXTERNAL-IP/hostname is allocated
kubectl -n ccm-check get svc web-lb -w
```

Output:
```bash
[h10h-aws-cluster-admin@h10h-aws-cluster|default] ➜  cloud-agnostic git:(main) ✗ kubectl apply -f clusters/aws/tests/aws-ccm-validate.yaml
namespace/ccm-check created
deployment.apps/web created
service/web-lb created
[h10h-aws-cluster-admin@h10h-aws-cluster|default] ➜  cloud-agnostic git:(main) ✗ kubectl -n ccm-check get svc web-lb -w

NAME     TYPE           CLUSTER-IP     EXTERNAL-IP                                                                     PORT(S)        AGE
web-lb   LoadBalancer   10.98.21.233   ab83894a2815c4c798e64f0554e21e12-8b0dffc33f8e775b.elb.us-east-1.amazonaws.com   80:30773/TCP   4m9s
```
If the `EXTERNAL-IP` shows an AWS NLB DNS name like `*.elb.amazonaws.com` then it's good 👍

Validate by accessing the service:
```bash
# Resolve & curl (repeat a couple of times to see NLB health)
LB=$(kubectl -n ccm-check get svc web-lb -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
getent hosts "$LB" || nslookup "$LB"
curl -I --max-time 5 "http://$LB/"
```

Output:
```bash
[h10h-aws-cluster-admin@h10h-aws-cluster|default] ➜  cloud-agnostic git:(main) ✗ LB=$(kubectl -n ccm-check get svc web-lb -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
[h10h-aws-cluster-admin@h10h-aws-cluster|default] ➜  cloud-agnostic git:(main) ✗ getent hosts "$LB" || nslookup "$LB"
Server:         192.168.1.1
Address:        192.168.1.1#53

Non-authoritative answer:
Name:   ab83894a2815c4c798e64f0554e21e12-8b0dffc33f8e775b.elb.us-east-1.amazonaws.com
Address: 35.171.98.45

[h10h-aws-cluster-admin@h10h-aws-cluster|default] ➜  cloud-agnostic git:(main) ✗ curl -I --max-time 5 "http://$LB/"
HTTP/1.1 200 OK
Server: nginx/1.25.5
Date: Sat, 18 Oct 2025 11:18:44 GMT
Content-Type: text/html
Content-Length: 615
Last-Modified: Tue, 16 Apr 2024 14:29:59 GMT
Connection: keep-alive
ETag: "661e8b67-267"
Accept-Ranges: bytes
```

If you get a `HTTP/1.1 200 OK.` response from the curl command then the CCM is working properly 🛜. Or you can access the service from your browser using the `EXTERNAL-IP` DNS name to verify.

### 2) AWS EBS CSI Driver (ebs-csi)
Things to verify:
- Controller & node components are healthy
- CSIDriver ebs.csi.aws.com exists
- Dynamic provisioning works (create StorageClass + PVC + Pod, write data, delete pod, re-attach, data persists)

```bash
# Controller & node daemonset
kubectl -n kube-system get deploy,ds | egrep -i 'ebs|csi' || true
kubectl get csidriver

# Controller logs (adjust pod name if different)
kubectl -n kube-system get pods -l app=ebs-csi-controller
CSI_CTLR=$(kubectl -n kube-system get pods -l app=ebs-csi-controller -o jsonpath='{.items[0].metadata.name}')
kubectl -n kube-system logs "$CSI_CTLR" --tail=200
```

Output:
```bash
[h10h-aws-cluster-admin@h10h-aws-cluster|default] ➜  cloud-agnostic git:(main) ✗ kubectl -n kube-system get deploy,ds | egrep -i 'ebs|csi' || true
deployment.apps/ebs-csi-controller        2/2     2            2           58m
daemonset.apps/ebs-csi-node                   2         2         2       2            2           kubernetes.io/os=linux                   58m
[h10h-aws-cluster-admin@h10h-aws-cluster|default] ➜  cloud-agnostic git:(main) ✗ kubectl get csidriver
NAME              ATTACHREQUIRED   PODINFOONMOUNT   STORAGECAPACITY   TOKENREQUESTS   REQUIRESREPUBLISH   MODES        AGE
ebs.csi.aws.com   true             false            false             <unset>         false               Persistent   58m
[h10h-aws-cluster-admin@h10h-aws-cluster|default] ➜  cloud-agnostic git:(main) ✗ kubectl -n kube-system get pods -l app=ebs-csi-controller
NAME                                  READY   STATUS    RESTARTS   AGE
ebs-csi-controller-567f558465-27w67   6/6     Running   0          59m
ebs-csi-controller-567f558465-kqdc4   6/6     Running   0          59m
[h10h-aws-cluster-admin@h10h-aws-cluster|default] ➜  cloud-agnostic git:(main) ✗ CSI_CTLR=$(kubectl -n kube-system get pods -l app=ebs-csi-controller -o jsonpath='{.items[0].metadata.name}')
kubectl -n kube-system logs "$CSI_CTLR" --tail=200

Defaulted container "ebs-plugin" out of: ebs-plugin, csi-provisioner, csi-attacher, csi-snapshotter, csi-resizer, liveness-probe
I1018 10:37:17.171113       1 main.go:154] "Initializing metadata"
I1018 10:37:17.171219       1 metadata.go:66] "Attempting to retrieve instance metadata from IMDS"
I1018 10:37:20.688492       1 metadata.go:69] "Retrieved metadata from IMDS"
I1018 10:37:20.689487       1 envvar.go:172] "Feature gate default state" feature="InOrderInformers" enabled=true
I1018 10:37:20.689515       1 envvar.go:172] "Feature gate default state" feature="InformerResourceVersion" enabled=false
I1018 10:37:20.689524       1 envvar.go:172] "Feature gate default state" feature="WatchListClient" enabled=false
I1018 10:37:20.689530       1 envvar.go:172] "Feature gate default state" feature="ClientsAllowCBOR" enabled=false
I1018 10:37:20.689536       1 envvar.go:172] "Feature gate default state" feature="ClientsPreferCBOR" enabled=false
I1018 10:37:20.690179       1 driver.go:72] "Driver Information" Driver="ebs.csi.aws.com" Version="v1.50.1"
```

Create resources to test dynamic provisioning:
```bash
kubectl apply -f clusters/aws/tests/ebs-csi-validate.yaml
# Wait bind + pod success
kubectl -n ebs-check get pvc data -w
kubectl -n ebs-check logs -f pod/writer
```

Output:
```bash
[h10h-aws-cluster-admin@h10h-aws-cluster|default] ➜  cloud-agnostic git:(main) ✗ kubectl -n ebs-check get pvc data
kubectl -n ebs-check logs -f pod/writer

NAME   STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
data   Bound    pvc-bd2ee68f-91f2-4bf8-8d98-8f2ef4699850   4Gi        RWO            ebs-gp3        <unset>                 6m31s
+ date '+%s'
+ echo hello-from-ebs-1760787463
+ cat /data/hello.txt
hello-from-ebs-1760787463
+ sleep 5
```

If the PVC status is `Bound` and logs print the `hello-from-ebs-...` line then the EBS CSI Driver is working properly 👍.

### 3) Calico (CNI & NetworkPolicy)

```bash
kubectl -n kube-system get ds,deploy | egrep -i 'calico' || true
kubectl get nodes -o custom-columns=NAME:.metadata.name,PODCIDR:.spec.podCIDR
kubectl get ippools.crd.projectcalico.org -o wide || true
```

Output:
```bash
[h10h-aws-cluster-admin@h10h-aws-cluster|default] ➜  cloud-agnostic git:(main) ✗ kubectl -n kube-system get ds,deploy | egrep -i 'calico' || true
kubectl get nodes -o custom-columns=NAME:.metadata.name,PODCIDR:.spec.podCIDR
kubectl get ippools.crd.projectcalico.org -o wide || true
daemonset.apps/calico-node                    2         2         2       2            2           kubernetes.io/os=linux                   76m
deployment.apps/calico-kube-controllers   1/1     1            1           76m
NAME                             PODCIDR
ip-192-168-28-111.ec2.internal   10.244.0.0/24
ip-192-168-30-212.ec2.internal   10.244.1.0/24
NAME                  AGE
default-ipv4-ippool   76m
```

If the Calico daemonset and deployment are running, nodes have PodCIDR assigned, and the default IP pool exists then Calico is working properly 👍.

## Cleanup the resources
Now that you've successfully created and validated an AWS workload cluster using Cluster API, you can proceed to deploy your applications or further customize the cluster as needed 🚀☸️

When you're done, don't forget to clean up the resources to avoid unnecessary costs:
```bash
kubectl delete cluster h10h-aws-cluster
```
