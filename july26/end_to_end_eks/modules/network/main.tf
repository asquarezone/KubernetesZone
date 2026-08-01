# ---------------------------------------------------------------------------
# Address plan (memorise this - it is the exam question)
#
#   VPC                    10.10.0.0/16
#   |- public  subnets     10.10.0.0/24, 10.10.1.0/24, 10.10.2.0/24
#   |                      -> internet-facing load balancers, NAT gateways
#   |- private subnets     10.10.16.0/20, 10.10.32.0/20, 10.10.48.0/20
#                          -> worker nodes AND pods
#
# THE BIG DIFFERENCE FROM AKS: the AWS VPC CNI gives every pod a REAL VPC IP
# from the node's subnet. There is no overlay by default. A /20 per AZ is 4091
# usable addresses, which sounds enormous until you notice that each node
# pre-allocates a warm pool of IPs and each t3.large can hold 35 pods.
#
#   nodes x pods-per-node = VPC IPs consumed
#
# This is why the private subnets here are /20 and not /24. Undersize them and
# the cluster autoscaler will add a node that never becomes Ready because the
# CNI cannot hand out addresses. Azure CNI Overlay does not have this problem;
# AWS VPC CNI does unless you enable prefix delegation or a custom network.
# ---------------------------------------------------------------------------

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true # REQUIRED by EKS for private endpoint resolution

  tags = merge(var.tags, { Name = "vpc-${var.suffix}" })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "igw-${var.suffix}" })
}

# ---------------------------------------------------------------------------
# Public subnets - load balancers and NAT gateways live here.
#
# The kubernetes.io/role/elb tag is not decoration: the AWS Load Balancer
# Controller discovers where to place an internet-facing ALB by looking for
# exactly this tag. Omit it and your Ingress will sit there with no address
# and a very unhelpful event message.
# ---------------------------------------------------------------------------
resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs)

  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.azs[count.index]
  map_public_ip_on_launch = true

  tags = merge(var.tags, {
    Name                     = "snet-public-${var.azs[count.index]}-${var.suffix}"
    "kubernetes.io/role/elb" = "1"
  })
}

resource "aws_subnet" "private" {
  count = length(var.private_subnet_cidrs)

  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  tags = merge(var.tags, {
    Name                              = "snet-private-${var.azs[count.index]}-${var.suffix}"
    "kubernetes.io/role/internal-elb" = "1"
  })
}

# ---------------------------------------------------------------------------
# NAT - the private subnets need outbound internet for image pulls and for the
# kubelet to reach the EKS control plane endpoint.
#
# COST WARNING: a NAT gateway bills per hour AND per GB processed. With
# single_nat_gateway = true you get one; set it false for one per AZ, which is
# what production wants (an AZ outage should not take out your egress) and
# roughly triples this line item.
# ---------------------------------------------------------------------------
resource "aws_eip" "nat" {
  count  = var.single_nat_gateway ? 1 : length(var.public_subnet_cidrs)
  domain = "vpc"
  tags   = merge(var.tags, { Name = "eip-nat-${count.index}-${var.suffix}" })

  depends_on = [aws_internet_gateway.this]
}

resource "aws_nat_gateway" "this" {
  count = var.single_nat_gateway ? 1 : length(var.public_subnet_cidrs)

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id
  tags          = merge(var.tags, { Name = "nat-${count.index}-${var.suffix}" })

  depends_on = [aws_internet_gateway.this]
}

# ---------------------------------------------------------------------------
# Routing
# ---------------------------------------------------------------------------
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "rt-public-${var.suffix}" })
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# One private route table per AZ so each can point at its own NAT when
# single_nat_gateway = false.
resource "aws_route_table" "private" {
  count  = length(var.private_subnet_cidrs)
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "rt-private-${var.azs[count.index]}-${var.suffix}" })
}

resource "aws_route" "private_nat" {
  count                  = length(aws_route_table.private)
  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = var.single_nat_gateway ? aws_nat_gateway.this[0].id : aws_nat_gateway.this[count.index].id
}

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# ---------------------------------------------------------------------------
# Security group for the worker nodes.
#
# EKS creates and manages the cluster security group itself; this one is for
# rules YOU own. The node-to-node allow-all is what lets pods on different
# nodes talk, which with the VPC CNI is real VPC traffic, not overlay traffic.
# ---------------------------------------------------------------------------
resource "aws_security_group" "nodes" {
  name        = "sg-nodes-${var.suffix}"
  description = "EKS worker node shared security group"
  vpc_id      = aws_vpc.this.id

  tags = merge(var.tags, { Name = "sg-nodes-${var.suffix}" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "nodes_self" {
  security_group_id            = aws_security_group.nodes.id
  referenced_security_group_id = aws_security_group.nodes.id
  ip_protocol                  = "-1"
  description                  = "Node to node, all ports - pod traffic is VPC traffic here"
}

resource "aws_vpc_security_group_egress_rule" "nodes_all" {
  security_group_id = aws_security_group.nodes.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "Outbound to anywhere (image pulls, control plane, AWS APIs)"
}
