terraform {
    required_providers {
      aws = {
        source  = "hashicorp/aws"
        version = "~> 4.16"
      }
    }

    required_version = ">= 1.2.0"
}

provider "aws" {
    region = var.region
}

resource "aws_vpc" "k8s_vpc" {
    cidr_block = "10.0.0.0/16"
    enable_dns_support   = true
    enable_dns_hostnames = true
    tags = {
        Name = "k8s_vpc"
    }
}

resource "aws_internet_gateway" "igw" {
    vpc_id = aws_vpc.k8s_vpc.id

    tags = {
        Name = "k8s_igw"
    }
}

#Public subnet
resource "aws_subnet" "public_subnet" {
    count = 2
    vpc_id            = aws_vpc.k8s_vpc.id
    cidr_block        = count.index == 0 ? "10.0.1.0/24" : "10.0.2.0/24"
    availability_zone = element(["us-east-1a", "us-east-1b"], count.index)
    map_public_ip_on_launch = true

    tags = {
        Name = "public_subnet_${count.index}"
    }
}

#Private subnet
resource "aws_subnet" "private_subnet" {
    count = 2
    vpc_id            = aws_vpc.k8s_vpc.id
    cidr_block        = count.index == 0 ? "10.0.3.0/24" : "10.0.4.0/24"
    availability_zone = element(["us-east-1a", "us-east-1b"], count.index)
    map_public_ip_on_launch = false

    tags = {
        Name = "private_subnet_${count.index}"
    }
}

resource "aws_instance" "bastion" {
    count = 2

    ami           = "ami-0c101f26f147fa7fd"
    instance_type = "t2.micro"
    key_name      = 
    subnet_id     = element(aws_subnet.public_subnet.*.id, count.index)

    vpc_security_group_ids = [aws_security_group.bastion_sg.id]

    associate_public_ip_address = true

    tags = {
        Name = "BastionHost-${count.index}"
    }
}

resource "aws_instance" "nat" {
    count = length(aws_subnet.public_subnet)

    ami           = "ami-0c101f26f147fa7fd"
    instance_type = "t2.micro"
    key_name      = 
    subnet_id     = element(aws_subnet.public_subnet.*.id, count.index)

    vpc_security_group_ids = [aws_security_group.nat_sg.id]

    source_dest_check = false
    associate_public_ip_address = true

    tags = {
        Name = "NATInstance-${count.index}"
    }
}

resource "aws_instance" "web_server_node" {
    count = length(aws_subnet.public_subnet)

    ami           = "ami-0c101f26f147fa7fd"
    instance_type = "t2.micro"
    key_name      =
    subnet_id     = aws_subnet.public_subnet[count.index].id

    vpc_security_group_ids = [aws_security_group.web_sg.id]
    user_data = file("setup-k8s-worker.sh") #need script

    tags = {
        Name = "WebServerNode=${count.index}"
    }
}

resource "aws_instance" "k8s_master" {
    count = length(aws_subnet.private_subnet)

    ami           = "ami-0c101f26f147fa7fd"
    instance_type = "t2.micro"
    key_name      =
    subnet_id     = element(aws_subnet.private_subnet.*.id, count.index)

    vpc_security_group_ids = [aws_security_group.k8s_sg.id]
    user_data = file("setup-k8s-master.sh") #need script

    tags = {
        Name = "K8sMasterNode-${count.index}"
    }
}

resource "aws_instance" "k8s_worker" {
    count = length(aws_subnet.private_subnet) * desired_worker_per_subnet

    ami           = "ami-0c101f26f147fa7fd"
    instance_type = "t2.micro"
    key_name      =
    subnet_id     = element(concat(aws_subnet.private_subnet.*.id, aws_subnet.private_subnet.*.id), count.index)

    vpc_security_group_ids = [aws_security_group.k8s_sg.id]
    user_data = file("setup-k8s-worker.sh") #need script

    tags = {
        Name = "K8sWorkerNode-${count.index}"
    }
}

resource "aws_instance" "jenkins" {
    count = 1

    ami           = "ami-0c101f26f147fa7fd"
    instance_type = "t2.micro"
    subnet_id     = aws_subnet.private_subnet[0].id
    key_name      = 

    vpc_security_group_ids = [aws_security_group.jenkins_sg.id]
    user_data = file("setup-jenkins.sh")

    tags = {
        Name = "JenkinsServer"
    }
}