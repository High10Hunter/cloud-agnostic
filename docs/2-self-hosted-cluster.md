# Convert Workload to Self-Hosted Cluster
**Before starting this section ensure you've completed all below sections: ** 
- [Prerequisites](./0-prerequisites.md).
- [Bootstrap AWS cluster](./1-bootstrap-aws-cluster.md).

## Convert workload cluster to self-hosted cluster 
Follow the steps in the [Bootstrap AWS cluster](./1-bootstrap-aws-cluster.md) guide to set up an ephemeral management cluster with KinD and a quick start workload cluster. We need to convert the quick start workload cluster into a self-hosted one.

```bash
# Connect to the workload cluster on AWS
clusterctl get kubeconfig h10h-aws-cluster > ~/.kube/h10h-aws-cluster.kubeconfig
kubie ctx h10h-aws-cluster-admin@h10h-aws-cluster 

# in the root of the repo
# The REGION variable should match the region used when bootstrapping the ephemeral management cluster
export AWS_B64ENCODED_CREDENTIALS=$(clusterawsadm bootstrap credentials encode-as-profile --region "$REGION")
clusterctl init --infrastructure aws --config ./bootstrap/clusterctl-config.yaml
```

Make sure that the Cluster API components are installed successfully by running:
```bash
kubie ctx h10h-aws-cluster-admin@h10h-aws-cluster 
kubectl get deployments -A
```

Output:
```bash
[h10h-aws-cluster-admin@h10h-aws-cluster|default] ➜  cloud-agnostic git:(main) ✗ kubectl get deployments -A
NAMESPACE                           NAME                                            READY   UP-TO-DATE   AVAILABLE   AGE
capa-system                         capa-controller-manager                         1/1     1            1           102s
capi-kubeadm-bootstrap-system       capi-kubeadm-bootstrap-controller-manager       1/1     1            1           2m44s
capi-kubeadm-control-plane-system   capi-kubeadm-control-plane-controller-manager   1/1     1            1           2m24s
capi-system                         capi-controller-manager                         1/1     1            1           3m2s
cert-manager                        cert-manager                                    1/1     1            1           3m59s
cert-manager                        cert-manager-cainjector                         1/1     1            1           4m
cert-manager                        cert-manager-webhook                            1/1     1            1           3m56s
kube-system                         calico-kube-controllers                         1/1     1            1           118m
kube-system                         coredns                                         2/2     2            2           119m
kube-system                         ebs-csi-controller                              2/2     2            2           119m
```

Move the Cluster API resources from ephemeral to the self-hosted cluster

```bash
# Switch back to your local KinD management cluster context
kubie ctx kind-capi-bootstrap
clusterctl move --to-kubeconfig ~/.kube/h10h-aws-cluster.kubeconfig 
```

Output:
```bash
Performing move...
Discovering Cluster API objects
Moving Cluster API objects Clusters=1
Moving Cluster API objects ClusterClasses=1
Waiting for all resources to be ready to move
Creating objects in the target cluster
[API Server Warning] Cluster refers to ClusterClass default/aws-quick-start, but this ClusterClass hasn't been successfully reconciled. Cluster topology has not been fully validated. Please take a look at the ClusterClass status
[API Server Warning] Cluster refers to ClusterClass default/aws-quick-start, but this ClusterClass hasn't been successfully reconciled. Cluster topology has not been fully validated. Please take a look at the ClusterClass status
Deleting objects from the source cluster
```

We have successfully made the quick start `h10h-aws-cluster` a self-hosted cluster. View the self-hosted cluster:

```bash
kubie ctx h10h-aws-cluster-admin@h10h-aws-cluster 
kubectl get clusters
```

Output:
```bash
[h10h-aws-cluster-admin@h10h-aws-cluster|default] ➜  cloud-agnostic git:(main) ✗ kubectl get clusters
NAME               CLUSTERCLASS      AVAILABLE   CP DESIRED   CP AVAILABLE   CP UP-TO-DATE   W DESIRED   W AVAILABLE   W UP-TO-DATE   PHASE         AGE   VERSION
h10h-aws-cluster   aws-quick-start   True        1            1              1               2           2             2              Provisioned   83s   v1.32.0
```

Notice that the `h10h-aws-cluster` is listed among the clusters that it is managing which means that we got a self-hosted cluster 🚀

## Clean up
In order to remove the self-hosted cluster on cloud we need to move the management cluster back to our local KinD cluster then delete the workload cluster on AWS.

```bash
kind get kubeconfig --name capi-bootstrap > capi-bootstrap.kubeconfig

# Switch to the self-hosted cluster context
kubie ctx h10h-aws-cluster-admin@h10h-aws-cluster
clusterctl move --to-kubeconfig capi-bootstrap.kubeconfig 

# Delete the workload cluster on AWS
kubectl delete cluster h10h-aws-cluster
```

## More information
You can find more about self-hosting a management cluster at the [`clusterctl pivot` section in the CAPI documentation](https://cluster-api.sigs.k8s.io/clusterctl/commands/move.html#pivot)
