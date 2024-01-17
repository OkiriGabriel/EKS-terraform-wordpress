module "wordpress-prod" {
  source       = "terraform-aws-modules/eks/aws"
  cluster_name = var.cluster_name
  subnet_ids   = module.app_vpc.private_subnets
  vpc_id       = module.app_vpc.vpc_id

  # eks_managed_node_groups = {
  #   prod = {
  #     instance_types = ["t2.small"]
  #     min_size       = 1
  #     max_size       = 3
  #     desired_size   = 3

  #     create_launch_template = false
  #     launch_template_name   = "aws"

  #     pre_bootstrap_user_data = <<-EOT
  #     echo "foo"
  #     export FOO=bar
  #     EOT

  #     bootstrap_extra_args = "--kubelet-extra-args '--node-labels=node.kubernetes.io/lifecycle=spot'"

  #     # SSM makes debugging worker nodes much easier
  #     post_bootstrap_user_data = <<-EOT
  #     cd /tmp
  #     sudo yum install -y https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/linux_amd64/amazon-ssm-agent.rpm
  #     sudo systemctl enable amazon-ssm-agent
  #     sudo systemctl start amazon-ssm-agent
  #     EOT

  #     tags = {
  #       key                 = "Name"
  #       value               = "wordpress-worker"
  #       propagate_at_launch = true
  #     }
  #   }
  # }

  cluster_addons = {
    kube-proxy = {}
  }

  tags = {
    environment = "prod"
  }
}

resource "aws_security_group" "node_sg_name" {
  name        = "allow_all_inbound"
  description = "Allow all inbound traffic"
  vpc_id      = module.db_vpc.vpc_id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"  # -1 means all protocols
    cidr_blocks = ["0.0.0.0/0"]  # Allow inbound traffic from all sources
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]  # Allow all outbound traffic
  }
}

resource "aws_eks_addon" "coredns" {
  cluster_name                = module.wordpress-prod.cluster_name
  addon_name                  = "coredns"
  addon_version               = "v1.10.1-eksbuild.6" #e.g., previous version v1.9.3-eksbuild.3 and the new version is v1.10.1-eksbuild.1
  resolve_conflicts_on_update = "PRESERVE"
}

resource "aws_eks_addon" "vpc-cni" {
  cluster_name                = module.wordpress-prod.cluster_name
  addon_name                  = "vpc-cni"
addon_version               = "v1.14.1-eksbuild.2" #e.g., previous version v1.9.3-eksbuild.3 and the new version is v1.10.1-eksbuild.1
}
module "eks_managed_node_group" {
  source = "terraform-aws-modules/eks/aws//modules/eks-managed-node-group"

  name            = "prod"
  cluster_name = module.wordpress-prod.cluster_name
  subnet_ids   = module.app_vpc.private_subnets
  # vpc_id       = module.app_vpc.vpc_id
  # cluster_version = "1.27"

  # subnet_ids = ["subnet-abcde012", "subnet-bcde012a", "subnet-fghi345a"]

  // The following variables are necessary if you decide to use the module outside of the parent EKS module context.
  // Without it, the security groups of the nodes are empty and thus won't join the cluster.
  cluster_primary_security_group_id = "${aws_security_group.node_sg_name.id}"
  vpc_security_group_ids            = [module.db_vpc.default_security_group_id]

  // Note: `disk_size`, and `remote_access` can only be set when using the EKS managed node group default launch template
  // This module defaults to providing a custom launch template to allow for custom security groups, tag propagation, etc.
   use_custom_launch_template = false
  // disk_size = 50
  //
  //  # Remote access cannot be specified with a launch template
  //  remote_access = {
  //    ec2_ssh_key               = module.key_pair.key_pair_name
  //    source_security_group_ids = [aws_security_group.remote_access.id]
  //  }

      instance_types = ["t2.small"]
      min_size       = 2
      max_size       = 5
      desired_size   = 5
  # instance_types = ["t3.large"]
  capacity_type  = "SPOT"

enable_bootstrap_user_data = true
 pre_bootstrap_user_data =  <<-EOT
      echo "foo"
      export FOO=bar
      EOT

      bootstrap_extra_args = "--kubelet-extra-args '--node-labels=node.kubernetes.io/lifecycle=spot'"

      # SSM makes debugging worker nodes much easier
      post_bootstrap_user_data = <<-EOT
      cd /tmp
      sudo yum install -y https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/linux_amd64/amazon-ssm-agent.rpm
      sudo systemctl enable amazon-ssm-agent
      sudo systemctl start amazon-ssm-agent
      EOT

  labels = {
    Environment = "test"
    GithubRepo  = "terraform-aws-eks"
    GithubOrg   = "terraform-aws-modules"
  }

  taints = {
    dedicated = {
      key    = "dedicated"
      value  = "gpuGroup"
      effect = "NO_SCHEDULE"
    }
  }

    tags = {
        key                 = "Name"
        value               = "wordpress-worker"
        propagate_at_launch = true
      }
}