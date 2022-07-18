provider "aws" {
  region = "us-east-2"
}
provider "tls" {}
provider "local" {}
provider "null" {}
provider "http" {}
provider "template" {}

locals {
  timestamp = timestamp() # provide time in UTC format
  current_time = formatdate("DD-MMM-YYYY_hh:mm:ss", local.timestamp)
}

# Resources for keypair
resource "tls_private_key" "tls_private_key" {
  algorithm = "RSA"
  rsa_bits = "2048"
}
resource "aws_key_pair" "aws_key_pair" {
  key_name = "Harish-keypair"
  public_key = tls_private_key.tls_private_key.public_key_openssh
}
resource "local_file" "private_key" {
  filename = "${aws_key_pair.aws_key_pair.key_name}.pem"
  content = tls_private_key.tls_private_key.private_key_pem
}

# EC2 resource
resource "aws_instance" "aws_instance" {
  ami = "ami-0eea504f45ef7a8f7"
  instance_type = "t2.micro"
  tags = {
    Name = "Harish"
  }
  key_name = aws_key_pair.aws_key_pair.key_name
}

# Resources to install, configure & access apache server
data "template_file" "index_html" {
  template = file("./index.html")
  vars = {
    server_name = "Harish"
    private_ip = aws_instance.aws_instance.private_ip
    public_ip = aws_instance.aws_instance.public_ip
    current_time = local.current_time
  }
}
resource "local_file" "index_html" {
  filename = "index1.html"
  content = data.template_file.index_html.rendered
}
resource "null_resource" "copy_index_html" {
  provisioner "file" {
    connection {
      type = "ssh"
      user = "ubuntu"
      host = aws_instance.aws_instance.public_ip
      private_key = tls_private_key.tls_private_key.private_key_pem
    }
    source = local_file.index_html.filename
    destination = "/tmp/${local_file.index_html.filename}"
  }
}
resource "null_resource" "install_apache" {
  depends_on = [
    null_resource.copy_index_html
  ]
  provisioner "remote-exec" { # use to execute commands/actions on the remote machines
    connection {
      type = "ssh"
      user = "ubuntu"
      host = aws_instance.aws_instance.public_ip
      private_key = tls_private_key.tls_private_key.private_key_pem
    }
    inline = [
      "sudo apt-get update -y",
      "sudo apt-get install -y apache2",
      "sudo cp /tmp/${local_file.index_html.filename} /var/www/html/${local_file.index_html.filename}"
    ]
  }
}
resource "null_resource" "access_apache" {
  depends_on = [
    null_resource.install_apache
  ]
  provisioner "local-exec" {
    command = "curl http://${aws_instance.aws_instance.public_ip}:80"
  }
}
data "http" "access_apache" {
  depends_on = [
    null_resource.install_apache
  ]
  url = "http://${aws_instance.aws_instance.public_ip}:80"
}

# EBS creation
resource "aws_ebs_volume" "ebsvolume" {
  availability_zone = aws_instance.aws_instance.availability_zone
  size = 1
  type = "gp2"
  tags = {
    Name = "Harish_EBS"
  }
}
resource "aws_volume_attachment" "aws_volume_attachement" {
  volume_id = aws_ebs_volume.ebsvolume.id
  instance_id = aws_instance.aws_instance.id
  device_name = "/dev/sdf"
  force_detach = true
}
# EFS Mount
resource "aws_efs_file_system" "myefs" {
  creation_token = "Harish_EFS"

  tags = {
    Name = "Harish_EFS"
  }
}
data "aws_vpc" "vpcid" {
  default = true
}
data "aws_subnets" "mysubnet" {
  filter {
    name = "vpc-id"
    values = [ data.aws_vpc.vpcid.id ]
  }
  filter {
    name = "tag:Type"
    values = ["private"]
  }
}
resource "aws_efs_mount_target" "aws_efs_mount_target" {
  count = length(data.aws_subnets.mysubnet.ids)
  file_system_id = aws_efs_file_system.myefs.id
  subnet_id = data.aws_subnets.mysubnet.ids[count.index]
}

output "aws_instance_public_ip" {
  value = aws_instance.aws_instance.public_ip
}
output "efs_mount_target_id_with_az_name" {
  value = [
    for mount_target in aws_efs_mount_target.aws_efs_mount_target: "Mount target az is ${mount_target.availability_zone_name} \n Mount target id ${mount_target.id}"
  ]
}