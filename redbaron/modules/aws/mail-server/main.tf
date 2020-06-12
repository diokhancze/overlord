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

resource "aws_key_pair" "mail-server" {
  count = "${var.count}"
  key_name = "mail-server-key-${random_id.server.*.hex[count.index]}"
  public_key = "${tls_private_key.ssh.*.public_key_openssh[count.index]}"
}

resource "aws_instance" "mail-server" {
  // Currently, variables in provider fields are not supported :(
  // This severely limits our ability to spin up instances in diffrent regions
  // https://github.com/hashicorp/terraform/issues/11578

  //provider = "aws.${element(var.regions, count.index)}"

  count = "${var.count}"

  tags = {
    Name = "mail-server-${random_id.server.*.hex[count.index]}"
  }

  ami = "${var.amis[data.aws_region.current.name]}"
  instance_type = "${var.instance_type}"
  key_name = "${aws_key_pair.mail-server.*.key_name[count.index]}"
  vpc_security_group_ids = ["${aws_security_group.mail-server.id}"]
  subnet_id = "${var.subnet_id}"
  associate_public_ip_address = true

  provisioner "local-exec" {
    command = "echo \"${tls_private_key.ssh.*.private_key_pem[count.index]}\" > ../../redbaron/data/ssh_keys/${self.public_ip} && echo \"${tls_private_key.ssh.*.public_key_openssh[count.index]}\" > ../../redbaron/data/ssh_keys/${self.public_ip}.pub && chmod 600 ../../redbaron/data/ssh_keys/*"
  }

  provisioner "local-exec" {
    when = "destroy"
    command = "rm ../../redbaron/data/ssh_keys/${self.public_ip}*"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo apt-get update",
      "sudo apt-get install -y tmux mosh"
    ]

    connection {
        type = "ssh"
        user = "admin"
        private_key = "${tls_private_key.ssh.*.private_key_pem[count.index]}"
    }
  }

  provisioner "file" {
    #source      = "../../redbaron/data/scripts/iredmail.sh"
    source = "${var.path}"
    destination = "/tmp/iredmail.sh"

    connection {
        type = "ssh"
        user = "admin"
        private_key = "${tls_private_key.ssh.*.private_key_pem[count.index]}"
    }
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/iredmail.sh",
      "sudo /tmp/iredmail.sh",
    ]

    connection {
        type = "ssh"
        user = "admin"
        private_key = "${tls_private_key.ssh.*.private_key_pem[count.index]}"
    }
  }

}

data "template_file" "ssh_config" {

  count    = "${var.count}"

  template = "${file("../../redbaron/data/templates/ssh_config.tpl")}"

  depends_on = ["aws_instance.mail-server"]

  vars {
    name = "dns_rdir_${aws_instance.mail-server.*.public_ip[count.index]}"
    hostname = "${aws_instance.mail-server.*.public_ip[count.index]}"
    user = "admin"
    identityfile = "${path.root}/data/ssh_keys/${aws_instance.mail-server.*.public_ip[count.index]}"
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
