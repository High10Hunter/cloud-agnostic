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
kubectl apply -f clusters/configmaps
## Expected output:
# configmap/aws-ccm-addon created
# configmap/cni-calico created
# configmap/aws-ebs-csi-driver-addon created

# 2) Apply the workload cluster manifest
kubectl apply -f clusters/capa-quickstart.yaml
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
