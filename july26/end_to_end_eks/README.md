# Pets, Pods & Pipelines — AWS edition

### An end-to-end EKS autoscaling playbook — Terraform, the AKS Store demo, and the cluster autoscaler under full observability

You will provision a production-shaped EKS cluster with Terraform, install the
cluster autoscaler and the AWS Load Balancer Controller, deploy the
[Azure-Samples/aks-store-demo](https://github.com/Azure-Samples/aks-store-demo)
microservices app, and then drive it hard enough to watch the **cluster
autoscaler** add and remove nodes — with Container Insights, Amazon Managed
Prometheus and Grafana watching.

**Follow the parts in order.** Every step states what to run, what you should
see, and what to do when it goes wrong. Do not skip Part 1 — most failed labs
die there, before Terraform ever runs.

> **This is the AWS sibling of the AKS lab.** Where the two clouds genuinely
> differ, the difference is called out in a box like this one. The biggest:
> **on EKS the cluster autoscaler does not exist until you install it.**

---

## What you will build

| Layer | Resources |
|---|---|
| Network | VPC `10.10.0.0/16`, public + private subnets across 3 AZs, IGW, NAT, node SG |
| Registry | ECR repository (IAM-only auth, no static creds) + pull rights on the node role |
| Cluster | EKS, VPC CNI, managed node groups, EKS access entries, OIDC provider |
| Autoscaling | Cluster autoscaler via IRSA + ASG auto-discovery tags, tuned flags |
| Security | IRSA for autoscaler / LB controller / EBS CSI, private nodes, SSM access |
| Ingress | AWS Load Balancer Controller → ALB routing straight to pod IPs |
| Monitoring | Container Insights, Amazon Managed Prometheus + managed scraper, Managed Grafana, control-plane logs, 3 metric alarms + 1 log-metric alarm, SNS |

### What you will learn

1. Why the HPA and the cluster autoscaler are a *relay*, not rivals.
2. That the cluster autoscaler reads **requests**, never usage — and how to
   watch an HPA hit `maxReplicas` while the node count never twitches.
3. That on EKS the autoscaler is **your workload**, discovered by **ASG tags**,
   authorised by **IRSA** — three separate things that must all be right.
4. That the VPC CNI spends **real subnet IPs on every pod**.
5. Why EC2 vCPU quota and CIDR planning are design constraints, not paperwork.

### Time and cost

- Provisioning: **~20 minutes** (EKS control plane ~10, node groups ~5).
- **This costs real money**: nodes, **NAT gateways** (per-hour *and* per-GB),
  ALB/NLBs, AMP ingestion, CloudWatch logs, and Managed Grafana if enabled.
- **Do Part 11 (teardown) at the end of every session.**

---

## Repository layout

```
end_to_end_eks/
├── backend.tf              remote state (S3, native locking)
├── providers.tf            hashicorp/aws + hashicorp/random ONLY
├── variables.tf            every knob, documented
├── locals.tf               naming, tagging, CIDR maths
├── main.tf                 module wiring + EKS access entries
├── outputs.tf              handy commands as outputs
├── envs/dev.example.tfvars lab defaults (copy to dev.tfvars; *.tfvars is gitignored)
├── modules/
│   ├── network/            VPC, subnets, IGW, NAT, routes, node SG
│   ├── ecr/                container registry + lifecycle policy
│   ├── eks/                cluster, node groups, OIDC, IRSA roles, add-ons
│   ├── observability/      AMP + scraper, Managed Grafana, SNS, log groups
│   └── monitoring/         CloudWatch alarms + log metric filter
├── k8s/                    HPA, PDB, Ingress, scale-anchor demo
└── scripts/                preflight, bootstrap, installs, deploy, load test
```

---

# Part 0 — Tools

### Step 0.1 — Check your toolchain

```bash
terraform version     # need >= 1.10 for S3 native state locking
aws --version         # need >= 2.15
kubectl version --client
helm version           # needed only for Part 7 (LB controller)
```

### Step 0.2 — Make the scripts executable

```bash
cd end_to_end_eks
chmod +x scripts/*.sh
```

---

# Part 1 — AWS account setup

### Step 1.1 — Authenticate

```bash
# Option A - SSO (what most orgs use)
aws sso login --profile <profile>
export AWS_PROFILE=<profile>

# Option B - static keys / CI
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...
export AWS_SESSION_TOKEN=...        # if using temporary credentials

export AWS_REGION=us-east-1
```

Confirm:

```bash
aws sts get-caller-identity
```

> **Careful:** these exports live only in the shell that ran them. A new
> terminal has no credentials and Terraform will fail with
> `NoCredentialProviders` or fall back to a different profile than you expect.

### Step 1.2 — Understand what permissions you need

Unlike Azure — where `Contributor` silently cannot create role assignments —
AWS has no such split. But this lab **creates IAM roles and policies**, which
many organisations restrict. You need, at minimum:

- `iam:CreateRole`, `AttachRolePolicy`, `CreatePolicy`, `CreateOpenIDConnectProvider`
- full `eks:*`, `ec2:*` (VPC), `ecr:*`, `logs:*`, `sns:*`, `cloudwatch:*`
- `aps:*` for Managed Prometheus, `grafana:*` if you enable Grafana

`AdministratorAccess` is the pragmatic classroom answer. If you get
`AccessDenied` mid-apply, that is the analogue of the AKS `AuthorizationFailed`
lesson: **creating resources and granting access are different powers.**

### Step 1.3 — Run the preflight check

```bash
./scripts/preflight.sh
```

This checks identity, **EC2 vCPU quota**, Elastic IP quota, and whether IAM
Identity Center is on (needed only for Grafana).

### Step 1.4 — Check your EC2 vCPU quota (the #1 cause of a failed apply)

A **brand-new AWS account frequently has an On-Demand Standard limit of just
5 vCPUs.** Each `t3.large` is 2 vCPU, so the default sizing here (2 system + 3
user = 10 vCPU) will not fit, and node groups fail with
`VcpuLimitExceeded` — usually after the control plane has already been built.

```bash
aws service-quotas get-service-quota \
  --service-code ec2 --quota-code L-1216C47A \
  --region "$AWS_REGION" --query 'Quota.Value' --output text
```

Request more if needed (approval is usually minutes to hours):

```bash
aws service-quotas request-service-quota-increase \
  --service-code ec2 --quota-code L-1216C47A \
  --desired-value 32 --region "$AWS_REGION"
```

Then keep `(system_max + user_max) x vCPU-per-instance` under the limit.

> **Lesson:** capacity is a design input. The autoscaler cannot invent quota,
> and `max_size` is a promise your account has to be able to keep.

### Step 1.5 — Understand what the add-ons cost you

The autoscaler counts **requests**, so every DaemonSet reduces what a node can
actually accept. On a `t3.large` (2 vCPU):

| | CPU |
|---|---|
| Capacity | `2000m` |
| Allocatable (after kube + eviction reserve) | `~1930m` |
| Add-on DaemonSets (VPC CNI, kube-proxy, CloudWatch agent, Fluent Bit) | `~400–700m` |
| Left for your workloads on a **fresh** node | `~1200–1500m` |

EKS's default footprint is **lighter than AKS's** (AKS turns on KEDA, VPA,
Gatekeeper and managed NGINX by default; EKS does not). But once you add the
LB controller and Container Insights the gap narrows.

**Measure it on your own instance type before you teach:**

```bash
kubectl describe nodes |
  awk '/^Name:/{n=$2} /Allocated resources/{f=1} f&&/cpu /{print n, $2, $3; f=0}'
```

This is why [k8s/04-scale-anchor.yaml](k8s/04-scale-anchor.yaml) requests
`500m` rather than a full vCPU.

> **Lesson:** "2 vCPUs per node" is not "2 vCPUs *for you* per node." Size
> against **allocatable minus DaemonSets**.

### Step 1.6 — Managed Grafana prerequisite (optional)

Amazon Managed Grafana cannot be created without an identity provider. It
requires **AWS IAM Identity Center** enabled in the account, or SAML.

This is a real difference from Azure, where a Grafana role assignment is all
you need. `enable_grafana` therefore **defaults to `false`** here. Turn on IAM
Identity Center in the console first, then set it `true`.

---

# Part 2 — Remote state backend

### Step 2.1 — Create the state bucket

```bash
./scripts/bootstrap-backend.sh
```

Creates a versioned, encrypted, public-access-blocked S3 bucket. **Copy the
bucket name it prints.**

> The script branches on region because `create-bucket` must *omit*
> `LocationConstraint` in `us-east-1` and *require* it everywhere else. That
> asymmetry has broken more bootstrap scripts than any other line in AWS.

### Step 2.2 — Point backend.tf at it

Edit [backend.tf](backend.tf):

```hcl
backend "s3" {
  bucket       = "tfstate-ekstore-123456789012-ab12cd"   # <-- yours
  key          = "eks-store/dev.terraform.tfstate"
  region       = "us-east-1"                              # <-- must match
  encrypt      = true
  use_lockfile = true
}
```

> **`use_lockfile` is S3 native locking and needs Terraform >= 1.10.** On older
> Terraform, remove it and add `dynamodb_table = "..."` with a table whose
> primary key is `LockID` (String).

---

# Part 3 — Configure the lab

```bash
cp envs/dev.example.tfvars envs/dev.tfvars
```

| Setting | What to put |
|---|---|
| `region` | must match `backend.tf` |
| `owner` | your name — becomes a tag on every resource |
| `alert_email` | your email, or `""` |
| `*_instance_type` / `*_max_count` | must fit your vCPU quota (Step 1.4) |
| `single_nat_gateway` | `true` for a cheap lab, `false` for production shape |
| `enable_grafana` | only `true` if Step 1.6 passed |

---

# Part 4 — Provision the infrastructure

```bash
terraform init
terraform fmt -recursive
terraform validate          # expect: Success! The configuration is valid.
terraform plan -var-file=envs/dev.tfvars -out=tfplan
terraform apply tfplan
```

**Expected:** `Apply complete!` after roughly 20 minutes.

Common apply-time failures:

| Error | Fix |
|---|---|
| `VcpuLimitExceeded` | Step 1.4 — quota too low or maxima too high |
| `AddressLimitExceeded` | Elastic IP quota; set `single_nat_gateway = true` |
| `AccessDenied` on `iam:*` | Step 1.2 — your principal cannot create roles |
| Grafana `ValidationException` | Step 1.6 — IAM Identity Center not enabled |
| `InvalidParameterException: subnets` | fewer than 2 AZs; EKS requires 2+ |

Then read the outputs:

```bash
terraform output
```

---

# Part 5 — Connect to the cluster

```bash
aws eks update-kubeconfig --region "$(terraform output -raw region)" \
  --name "$(terraform output -raw cluster_name)"

kubectl get nodes -L nodepool-type
```

**Expected:** two `Ready` nodes — one `system`, one `user` (each group's
`min_size` is 1).

> **Unlike AKS, the system pool does *not* immediately jump to its max**,
> because EKS's default add-on set is much lighter. If you see it grow later,
> that is Container Insights and the LB controller arriving.

> **`error: You must be logged in to the server (Unauthorized)`** means your
> current IAM principal is not the one that created the cluster. Terraform
> granted admin to the *creating* principal only. Add yourself with
> `additional_admin_principal_arn` in tfvars and re-apply.

---

# Part 6 — Install the cluster autoscaler

> **This part has no equivalent in the AKS lab.** There, the autoscaler was
> already running the moment the cluster existed. Here, nothing autoscales
> until you do this.

```bash
./scripts/install-autoscaler.sh
```

The script applies the upstream manifest, annotates the ServiceAccount with
the IRSA role Terraform created, and patches the flags to match the AKS lab's
`auto_scaler_profile` (least-waste expander, 10s scan, 5m scale-down).

### Verify all three legs

An autoscaler can be *running* and still be useless if any leg is wrong.

```bash
# 1. Is it up?
kubectl -n kube-system get deploy cluster-autoscaler

# 2. Did IRSA work? (no AccessDenied in the logs)
kubectl -n kube-system logs deploy/cluster-autoscaler | grep -i "error\|denied" | head

# 3. Did auto-discovery find your node groups?
kubectl -n kube-system logs deploy/cluster-autoscaler | grep -i "node group" | head
```

**Expected on leg 3:** lines naming the `system` and `user` ASGs. If it found
none, the ASG tags are wrong — and the autoscaler will sit there happily doing
nothing, **with no error at all.**

> **Lesson:** three independent things must be right — the Deployment, the
> IAM trust (IRSA), and the discovery tags. Two out of three fails silently.

---

# Part 7 — Install the ingress controller

```bash
./scripts/install-lb-controller.sh
```

Downloads the current official IAM policy, attaches it to the role Terraform
created, and installs the controller with Helm.

> **Different from AKS.** `web_app_routing` gave you a managed NGINX pod and
> one shared IP. Here there is **no in-cluster proxy**: the controller creates
> a real ALB that routes straight to pod IPs (possible because the VPC CNI
> gives pods real VPC addresses). The `group.name` annotation in
> [k8s/03-ingress.yaml](k8s/03-ingress.yaml) puts both Ingress objects behind
> **one** ALB instead of paying for two.

---

# Part 8 — Deploy the application

```bash
./scripts/deploy-app.sh
kubectl -n pets get pods,svc,hpa,ingress
```

**Expected:** `store-front`, `store-admin`, `order-service`, `product-service`,
`makeline-service`, `rabbitmq`, `documentdb`, `virtual-customer`,
`virtual-worker` all `Running`, and two HPAs reporting live targets.

### Reach it

```bash
ALB=$(kubectl -n pets get ingress store-front \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "$ALB"
curl -s -o /dev/null -w "%{http_code}\n" "http://$ALB/"
```

**Expected:** `200`. An ALB takes 2–3 minutes to become active — until then
you get connection errors, not a Kubernetes problem.

> **Note:** upstream also declares `store-front` and `store-admin` as
> `type: LoadBalancer`, so AWS provisions **NLBs for them in addition** to
> your ALB. Billable, and another reason to tear down.

---

# Part 9 — Prove the cluster autoscaler works

**The relay:** load → HPA adds **pods** → pods go **Pending** → CA adds
**nodes**. Pending pods are the *only* trigger.

### Step 9.1 — Three watch terminals

```bash
kubectl get nodes -w                                    # Terminal 1
kubectl -n pets get hpa -w                              # Terminal 2
kubectl -n kube-system logs -f deploy/cluster-autoscaler # Terminal 3
```

> **Terminal 3 is the big difference from AKS.** There, the autoscaler's
> reasoning went to Log Analytics as a control-plane diagnostic category. Here
> the autoscaler is *your* pod, so you read its logs with `kubectl`. There is
> no `cluster-autoscaler` log type in CloudWatch — do not go looking for it.

### Step 9.2 — Exercise A: deterministic scale-up

```bash
kubectl -n pets scale deploy/scale-anchor --replicas=3
kubectl -n pets get pods -l app=scale-anchor -o wide -w
```

Watch Terminal 3 for `scale_up: setting group ... size to N`, then the node
appearing in Terminal 1. New EC2 nodes take 2–4 minutes to become `Ready`.

### Step 9.3 — Exercise B: hitting the ceiling

```bash
kubectl -n pets scale deploy/scale-anchor --replicas=12
sleep 90
kubectl -n pets describe pod -l app=scale-anchor | sed -n '/Events:/,$p' | head -20
```

**Expected:** the group grows to `max_size`, stops, and surplus pods stay
`Pending` with `max node group size reached`.

> **Lesson:** `max_size` is a hard ceiling. Pending-at-the-ceiling is the
> autoscaler doing exactly what you configured. "Autoscaling" never means
> "unlimited."

### Step 9.4 — Exercise C: HPA under load (the important one)

```bash
kubectl -n pets scale deploy/scale-anchor --replicas=0
./scripts/load-test.sh
```

Both HPAs will climb to `maxReplicas` — and **the node count will not move.**

Upstream sets `requests.cpu: 1m` on `store-front`. Thirty replicas request
`30m` *in total*. The pods are genuinely busy, but to the scheduler they are
nearly weightless, so nothing goes `Pending` and the autoscaler correctly does
nothing.

Prove the diagnosis:

```bash
kubectl -n pets set resources deploy/store-front --requests=cpu=200m
```

Now the same replica count carries real scheduling weight, pods go `Pending`,
and the group grows.

> **Lesson:** the HPA scales on **usage**. The cluster autoscaler schedules on
> **requests**. Mismatch them and you get a pegged CPU graph next to a flat
> node graph. This is the most common autoscaling bug in production.

### Step 9.5 — Scale-down

```bash
kubectl -n pets scale deploy/scale-anchor --replicas=0
kubectl -n pets delete job loadgen --ignore-not-found
kubectl -n pets set resources deploy/store-front --requests=cpu=1m
kubectl get nodes -w
```

Nodes drain and terminate after ~5–10 minutes, gated by PDBs and the
`--skip-nodes-with-*` flags.

---

# Part 10 — Observability

### Container Insights

CloudWatch console → Insights → Container Insights → your cluster.

### Managed Prometheus + Grafana

```bash
terraform output amp_query_endpoint
terraform output grafana_endpoint
```

In Grafana, add a Prometheus data source pointing at the AMP endpoint with
**SigV4 auth enabled**, region set to your region.

```promql
sum(rate(container_cpu_usage_seconds_total{namespace="pets"}[5m])) by (pod)
kube_pod_status_phase{namespace="pets", phase="Pending"}
count(kube_node_info)
```

> **If Grafana shows "no data":** on Azure the culprit is a missing DCR
> association. Here it is the **AMP scraper** — an AMP workspace with no
> scraper collects nothing. Same lesson, different noun.

### Alarms

Three CloudWatch alarms plus one log-metric alarm, wired to SNS.

> **Confirm your SNS subscription.** AWS emails a confirmation link; until you
> click it the subscription is `PendingConfirmation` and delivers nothing —
> even though Terraform reports it as created.

---

# Part 11 — Teardown

> **Do this at the end of every session.** NAT gateways and load balancers
> bill by the hour whether or not anyone is using them.

### Step 11.1 — Release cluster-created AWS resources first

```bash
./scripts/teardown-helpers.sh
```

This deletes the `pets` namespace and waits for the load balancers to go.

> **Why this matters more on AWS than on Azure.** The ALB and the NLBs were
> created by the *LB controller*, not by Terraform. Terraform does not know
> they exist and will not delete them — but they hold ENIs in your subnets,
> and **VPC deletion will fail** with a dependency error that names an ENI and
> nothing else. Delete the workloads first.

> **If node group deletion hangs**, check for PodDisruptionBudgets that cannot
> be satisfied:
> ```bash
> kubectl get pdb -A   # anything with ALLOWED DISRUPTIONS = 0 blocks the drain
> ```
> A PDB blocks *you* exactly as it blocks the autoscaler. Delete the blockers.

### Step 11.2 — Destroy

```bash
terraform destroy -var-file=envs/dev.tfvars
```

### Step 11.3 — Verify nothing survived

```bash
aws eks list-clusters --region "$AWS_REGION"
aws ec2 describe-vpcs --region "$AWS_REGION" \
  --filters "Name=tag:project,Values=ekstore" --query 'Vpcs[].VpcId'
aws elbv2 describe-load-balancers --region "$AWS_REGION" \
  --query 'LoadBalancers[].LoadBalancerName'
# Log groups are the classic survivor:
aws logs describe-log-groups --region "$AWS_REGION" \
  --log-group-name-prefix /aws/eks --query 'logGroups[].logGroupName'
```

The state bucket is deliberately **not** destroyed.

---

# Appendix A — Troubleshooting

| Symptom | Root cause | Lesson |
|---|---|---|
| `Permission denied` on `./scripts/...` | missing exec bit | `chmod +x scripts/*.sh` |
| `VcpuLimitExceeded` | EC2 quota below the cluster's ceiling | capacity is a design input |
| Autoscaler runs but never scales | ASG discovery tags wrong | it fails **silently** — check the logs |
| Autoscaler logs `AccessDenied` | IRSA trust or policy wrong | three legs must all be right |
| Pods `Pending`, no scale-up, no CA at all | you skipped Part 6 | EKS ships no autoscaler |
| Nodes `Ready` but pods stuck `ContainerCreating` | VPC CNI out of subnet IPs | every pod costs a real VPC IP |
| HPA shows `<unknown>` | metrics-server missing, or no CPU request | `Utilization` is a % *of the request* |
| Ingress never gets an address | LB controller not installed, or public subnets missing `kubernetes.io/role/elb` | the tag *is* the discovery |
| `You must be logged in to the server` | your IAM principal has no access entry | creator-only admin by default |
| VPC won't delete | ALB/NLB ENIs still present | delete workloads before infrastructure |
| Grafana `ValidationException` | IAM Identity Center not enabled | AMG needs an IdP; AMG ≠ Azure Grafana |
| Billed after destroy | log groups / EBS volumes / EIPs survive | destroy is not a billing guarantee |

---

# Appendix B — Architecture

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md), including a full
AKS↔EKS difference table.

Address plan:

```
VPC                  10.10.0.0/16
|- public  subnets   10.10.0.0/24, 10.10.1.0/24, 10.10.2.0/24   -> ALBs, NAT
|- private subnets   10.10.16.0/20, 10.10.32.0/20, 10.10.48.0/20 -> nodes AND pods

Service CIDR         172.20.0.0/16   MUST NOT overlap the VPC
```

The private subnets are `/20` and not `/24` on purpose: with the VPC CNI,
**pods consume real subnet addresses**, and each node pre-allocates a warm
pool. `nodes x pods-per-node` is your real IP budget.

---

# Appendix C — Provider policy

Only **HashiCorp-published providers**: `hashicorp/aws` and `hashicorp/random`.

```bash
terraform providers   # should list exactly two, both hashicorp/
```

Two deliberate consequences:

1. **No `hashicorp/tls`.** Most EKS tutorials use `data.tls_certificate` to
   compute the OIDC thumbprint. We use the documented constant instead — IAM
   no longer validates it for EKS-hosted issuers.
2. **No `kubernetes` or `helm` provider.** Configuring those from an output of
   a cluster that does not yet exist is the classic chicken-and-egg apply
   failure — it works for whoever wrote it and fails for every student. In-cluster
   components are installed by `scripts/` *after* the cluster exists. This is
   also why Parts 6 and 7 are separate steps rather than part of `apply`.

---

# Appendix D — Design notes

- `desired_size` is in `ignore_changes` on every node group — it belongs to
  the autoscaler. Leaving it under Terraform's control causes permanent drift
  and scales your cluster back down on every apply.
- The control-plane CloudWatch log group is created **explicitly** so that
  `destroy` removes it. Let EKS create it implicitly and it survives teardown,
  quietly accruing charges.
- `authentication_mode = "API"` uses EKS access entries rather than the legacy
  `aws-auth` ConfigMap — far harder to lock yourself out of.
- `scale-anchor` requests `500m`, not a full vCPU, because add-on DaemonSets
  already claim a large slice of a 2 vCPU node. Raise it on larger instances.
- `load-test.sh` sets Job **parallelism** at creation time; `kubectl scale`
  does not support Jobs.
- The Spot node group offers several instance types on purpose — a single type
  is far more likely to be interrupted or unavailable.
