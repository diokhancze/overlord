terraform {
  required_version = ">= 0.11.0"
}

data "aws_region" "current" {}

resource "random_id" "server" {
  count = "${var.count}"
  byte_length = 4
}

resource "tls_private_key" "ssh" {
  count = "${var.count}"
  algorithm = "RSA"
  rsa_bits = 4096
}

resource "aws_key_pair" "dns-c2" {
  count = "${var.count}"
  key_name = "dns-c2-key-${random_id.server.*.hex[count.index]}"
  public_key = "${tls_private_key.ssh.*.public_key_openssh[count.index]}"
}

resource "aws_instance" "dns-c2" {
  // Currently, variables in provider fields are not supported :(
  // This severely limits our ability to spin up instances in diffrent regions
  // https://github.com/hashicorp/terraform/issues/11578

  //provider = "aws.${element(var.regions, count.index)}"

  count = "${var.count}"

  tags = {
    Name = "dns-c2-${random_id.server.*.hex[count.index]}"
  }

  ami = "${var.amis[data.aws_region.current.name]}"
  instance_type = "${var.instance_type}"
  key_name = "${aws_key_pair.dns-c2.*.key_name[count.index]}"
  vpc_security_group_ids = ["${aws_security_group.dns-c2.id}"]
  subnet_id = "${var.subnet_id}"
  associate_public_ip_address = true

  provisioner "remote-exec" {
    scripts = "${concat(list("../../redbaron/data/scripts/core_deps.sh"), var.install)}"

    connection {
        type = "ssh"
        user = "${var.user}"
        private_key = "${tls_private_key.ssh.*.private_key_pem[count.index]}"
    }
  }

  provisioner "local-exec" {
    command = "echo \"${tls_private_key.ssh.*.private_key_pem[count.index]}\" > ../../redbaron/data/ssh_keys/${self.public_ip} && echo \"${tls_private_key.ssh.*.public_key_openssh[count.index]}\" > ../../redbaron/data/ssh_keys/${self.public_ip}.pub && chmod 600 ../../redbaron/data/ssh_keys/*"
  }

  provisioner "local-exec" {
    when = "destroy"
    command = "rm ../../redbaron/data/ssh_keys/${self.public_ip}*"
  }

}

data "template_file" "ssh_config" {

  count    = "${var.count}"

  template = "${file("../../redbaron/data/templates/ssh_config.tpl")}"

  depends_on = ["aws_instance.dns-c2"]

  vars {
    name = "dns_c2_${aws_instance.dns-c2.*.public_ip[count.index]}"
    hostname = "${aws_instance.dns-c2.*.public_ip[count.index]}"
    user = "${var.user}"
    identityfile = "${path.root}/data/ssh_keys/${aws_instance.dns-c2.*.public_ip[count.index]}"
  }

}

resource "null_resource" "gen_ssh_config" {

  count = "${var.count}"

  triggers {
    template_rendered = "${data.template_file.ssh_config.*.rendered[count.index]}"
  }

  provisioner "local-exec" {
    command = "echo '${data.template_file.ssh_config.*.rendered[count.index]}' > ../../redbaron/data/ssh_configs/config_${random_id.server.*.hex[count.index]}"
  }

  provisioner "local-exec" {
    when = "destroy"
    command = "rm ../../redbaron/data/ssh_configs/config_${random_id.server.*.hex[count.index]}"
  }

}
