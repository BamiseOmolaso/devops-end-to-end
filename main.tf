#############################################################
# Fetch the latest Ubuntu 24.04 LTS AMI dynamically
#############################################################

data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  owners = ["099720109477"]
}

#############################################################
# Web Server Instance 1
#############################################################

resource "aws_instance" "instance_1" {
  ami             = data.aws_ami.ubuntu.id
  instance_type   = "t2.micro"
  security_groups = [aws_security_group.instances.name]
  user_data       = <<-EOF
              #!/bin/bash
              echo "Hello, World 1" > index.html
              python3 -m http.server 8080 &
              EOF
}

#############################################################
# Web Server Instance 2
#############################################################

resource "aws_instance" "instance_2" {
  ami             = data.aws_ami.ubuntu.id
  instance_type   = "t2.micro"
  security_groups = [aws_security_group.instances.name]
  user_data       = <<-EOF
              #!/bin/bash
              echo "Hello, World 2" > index.html
              python3 -m http.server 8080 &
              EOF
}

#############################################################
# Security group for the instances
#############################################################

resource "aws_security_group" "instances" {
  name = "instance-security-group"
}

resource "aws_security_group_rule" "allow_http_inbound" {
  type              = "ingress"
  security_group_id = aws_security_group.instances.id

  from_port   = 8080
  to_port     = 8080
  protocol    = "tcp"
  cidr_blocks = ["0.0.0.0/0"]
}

#############################################################
# Create S3 bucket
#############################################################

resource "aws_s3_bucket" "bucket" {
  bucket_prefix = "devops-end-to-end-web-app-data"
  force_destroy = true
}

resource "aws_s3_bucket_versioning" "bucket_versioning" {
  bucket = aws_s3_bucket.bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "bucket_crypto_conf" {
  bucket = aws_s3_bucket.bucket.bucket
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

#############################################################
# Use default VPC
#############################################################

resource "aws_default_vpc" "default" {
  tags = {
    Name = "Default VPC"
  }
}


resource "aws_default_subnet" "default_az1" {
  availability_zone = "us-east-1a"

  tags = {
    Name = "Default subnet for us-east-1a"
  }
}

resource "aws_default_subnet" "default_az2" {
  availability_zone = "us-east-1b"

    tags = {
    Name = "Default subnet for us-east-1b"
  }
}


#############################################################
# Set Up Load Balancer
# We have two virtual machines and want to split traffic between them. We can do this with a load balancer. 
# We configure the load balancer behavior and attach the two EC2 instances to it.
#############################################################

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.load_balancer.arn
  port              = 80
  protocol          = "HTTP"
  # By default, return a simple 404 page
  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "404: page not found"
      status_code  = 404
    }
  }
}

resource "aws_lb_target_group" "instances" {
  name     = "example-target-group"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = aws_default_vpc.default.id
  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 15
    timeout             = 3
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_target_group_attachment" "instance_1" {
  target_group_arn = aws_lb_target_group.instances.arn
  target_id        = aws_instance.instance_1.id
  port             = 8080
}

resource "aws_lb_target_group_attachment" "instance_2" {
  target_group_arn = aws_lb_target_group.instances.arn
  target_id        = aws_instance.instance_2.id
  port             = 8080
}

resource "aws_lb_listener_rule" "instances" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 100
  condition {
    path_pattern {
      values = ["*"]
    }
  }
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.instances.arn
  }
}

resource "aws_security_group" "alb" {
  name = "alb-security-group"
}

resource "aws_security_group_rule" "allow_alb_http_inbound" {
  type              = "ingress"
  security_group_id = aws_security_group.alb.id
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "allow_alb_all_outbound" {
  type              = "egress"
  security_group_id = aws_security_group.alb.id
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]

}

resource "aws_lb" "load_balancer" {
  name               = "web-app-lb"
  load_balancer_type = "application"
  subnets            = [
    aws_default_subnet.default_az1.id,
    aws_default_subnet.default_az2.id
  ]
  security_groups    = [aws_security_group.alb.id]
}

#############################################################
# Configure Route 53 for DNS
# You will also need to update your domain's nameservers to use the AWS nameservers.
#############################################################

# resource "aws_route53_zone" "primary" {
#   name = "devopsdeployed.com"
# }

# resource "aws_route53_record" "root" {
#   zone_id = aws_route53_zone.primary.zone_id
#   name    = "devopsdeployed.com"
#   type    = "A"
#   alias {
#     name                   = aws_lb.load_balancer.dns_name
#     zone_id                = aws_lb.load_balancer.zone_id
#     evaluate_target_health = true
#   }
# }

#############################################################
# Our application does not actually use the RDS instance, 
# but we provision one to demonstrate how because most web applications will need a database of some kind.
#############################################################
# resource "aws_db_instance" "db_instance" {
#   allocated_storage = 20
#   # This allows any minor version within the major engine_version
#   # defined below, but will also result in allowing AWS to auto
#   # upgrade the minor version of your DB. This may be too risky
#   # in a real production environment.
#   auto_minor_version_upgrade = true
#   storage_type               = "standard"
#   engine                     = "postgres"
#   engine_version             = "12"
#   instance_class             = "db.t2.micro"
#   name                       = "mydb"
#   username                   = "foo"
#   password                   = "foobarbaz"
#   skip_final_snapshot        = true
# }