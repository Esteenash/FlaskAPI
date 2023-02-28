# vpc

resource "aws_vpc" "flask_vpc" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "Flask-VPC"
  }
}

# public subnets

resource "aws_subnet" "public_subnet" {
  # count             = 2
  vpc_id            = aws_vpc.flask_vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "eu-west-2a"

  tags = {
    Name = "PublicSubnet"
  }
}

# private subnets

resource "aws_subnet" "private_subnet" {
  count             = 2
  vpc_id            = aws_vpc.flask_vpc.id
  cidr_block        = cidrsubnet(aws_vpc.flask_vpc.cidr_block, 9, count.index)
  availability_zone = element(data.aws_availability_zones.available.names, count.index)

  tags = {
    Name = "PrivateSubnet"
  }
}

# internet gateway

resource "aws_internet_gateway" "internet_gateway" {
  vpc_id = aws_vpc.flask_vpc.id

  tags = {
    Name = "InternetGateway"
  }
}

#Create Nat Gateway
/*resource "aws_nat_gateway" "Nat_gateway" {
  allocation_id = aws_eip.flask_eip.id
  subnet_id     = aws_subnet.public_subnet.id


  tags = {
    Name = "Nat_Gateway"
  }
  depends_on = [aws_internet_gateway.internet_gateway]
}
*/

# routing

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.flask_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.internet_gateway.id
  }

  tags = {
    Name = "PublicRouteTable"
  }
}

resource "aws_route_table_association" "public_route_table_assoc" {
  count          = 2
  subnet_id      = element(aws_subnet.public_subnet.*.id, count.index)
  route_table_id = aws_route_table.public_route_table.id
}

# security group

resource "aws_security_group" "security_group" {
  name   = "SecurityGroup"
  vpc_id = aws_vpc.flask_vpc.id

  ingress {
    description = "Allow Port 443"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Create AWS EC2 Instances
resource "aws_instance" "flask_ec2" {
  ami = data.aws_ami.amzlinux2.id
  instance_type = "t2.micro"
  subnet_id = aws_subnet.private_subnet [0].id
  

  tags = {
    "Name" = "flask_ec2"
  }
}

resource "aws_eip" "flask_eip" {
  instance = aws_instance.flask_ec2.id
  vpc      = true
}


# Define an ECS cluster
resource "aws_ecs_cluster" "flask_cluster" {
  name = "flask-cluster"
}

# Define a task definition for the Flask API container
resource "aws_ecs_task_definition" "flask_task_definition" {
  family = "flask-task"
  container_definitions = jsonencode([{
    name  = "flask-api"
    image = "public.ecr.aws/t0r1n7t9/flask_api/flask_api:latest"
    portMappings = [{
      containerPort = 5000
      hostPort      = 0
    }]
    essential         = true
    memoryReservation = 128
    cpu               = 256
  }])
}

# Define a service that will run the Flask API container
resource "aws_ecs_service" "flask_service" {
  name            = "flask-service"
  cluster         = aws_ecs_cluster.flask_cluster.id
  task_definition = aws_ecs_task_definition.flask_task_definition.arn
  desired_count   = 2
  #iam_role        = aws_iam_role.ecs_task_execution_role.name

  /*Configure a load balancer to route traffic to the service
  load_balancer {
    target_group_arn = aws_alb_target_group.flask_target_group.arn
    container_name   = "flask-api"
    container_port   = 5000
  }
  */
}

/*Define an Application Load Balancer (ALB) and listener rules to route traffic to the service
resource "aws_lb" "flask_alb" {
  name               = "flask-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.security_group.id]
  subnets            = [aws_subnet.public_subnet[0].id]
}

# Define a listener rule to forward traffic to the ECS service
resource "aws_lb_listener_rule" "flask_listener_rule" {
  listener_arn = aws_lb_listener.http_listener.arn

  action {
    type             = "forward"
    target_group_arn = aws_alb_target_group.flask_target_group.arn
  }

  condition {
    path_pattern {
      values = ["/api/*"]
    }
  }
}

# Define a target group to route traffic to the ECS service
resource "aws_alb_target_group" "flask_target_group" {
  name     = "flask-target-group"
  port     = 5000
  protocol = "HTTP"
  vpc_id   = aws_vpc.flask_vpc.id

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    interval            = 30
    path                = "/"
    port                = "traffic-port"
  }

  depends_on = [aws_lb_target_group_attachment.flask_target_group_attachment]
}

# Attach the target group to the ALB
resource "aws_lb_target_group_attachment" "flask_target_group_attachment" {
  target_group_arn = aws_alb_target_group.flask_target_group.arn
  target_id        = aws_ecs_service.flask_service.id
  port             = 5000
}
*/

# execution role
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ecsTaskExecutionRole"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy_attachment" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
} 