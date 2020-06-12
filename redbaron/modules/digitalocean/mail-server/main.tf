terraform {
  required_version = ">= 0.11.0"
}

resource "random_id" "server" {
  count = "${var.counter}"
  byte_length = 4
}

resource "tls_private_key" "ssh" {
  count = "${var.counter}"
  algorithm = "RSA"
  rsa_bits = 4096
}

resource "digitalocean_ssh_key" "ssh_key" {
  count = "${var.counter}"
  name  = "mail-server-key-${random_id.server.*.hex[count.index]}"
  public_key = "${tls_private_key.ssh.*.public_key_openssh[count.index]}"
}

resource "digitalocean_droplet" "mail-server" {
  count = "${var.counter}"
  image = "debian-9-x64"
  name = "${var.name}" #"mail-server-${random_id.server.*.hex[count.index]}" #
  region = "${var.available_regions[element(var.regions, count.index)]}"
  ssh_keys = ["${digitalocean_ssh_key.ssh_key.*.id[count.index]}"]
  size = "${var.size}"

  provisioner "remote-exec" {
    inline = [
      "apt-get update",
      "apt-get install -y tmux mosh",
    ]

    connection {
        host = "${self.ipv4_address}"
        type = "ssh"
        user = "root"
        private_key = "${tls_private_key.ssh.*.private_key_pem[count.index]}"
    }
  }

  provisioner "local-exec" {
    command = "echo \"${tls_private_key.ssh.*.private_key_pem[count.index]}\" > ../../redbaron/data/ssh_keys/${self.ipv4_address} && echo \"${tls_private_key.ssh.*.public_key_openssh[count.index]}\" > ../../redbaron/data/ssh_keys/${self.ipv4_address}.pub && chmod 600 ../../redbaron/data/ssh_keys/*" 
  }

  provisioner "local-exec" {
    when = "destroy"
    command = "rm ../../redbaron/data/ssh_keys/${self.ipv4_address}*"
  }
  provisioner "file" {
    #source      = "../../redbaron/data/scripts/iredmail.sh"
    source = "${var.path}"
    destination = "/tmp/iredmail.sh"
        connection {
        host = "${self.ipv4_address}"
        type = "ssh"
        user = "root"
        private_key = "${tls_private_key.ssh.*.private_key_pem[count.index]}"
    }
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/iredmail.sh",
      "/tmp/iredmail.sh",
    ]

    connection {
        host = "${self.ipv4_address}"
        type = "ssh"
        user = "root"
        private_key = "${tls_private_key.ssh.*.private_key_pem[count.index]}"
    }
  }  
}

data "template_file" "ssh_config" {

  count    = "${var.counter}"

  template = "${file("../../redbaron/data/templates/ssh_config.tpl")}"

  depends_on = ["digitalocean_droplet.mail-server"]

  vars {
    name = "mail_server_${digitalocean_droplet.mail-server.*.ipv4_address[count.index]}"
    hostname = "${digitalocean_droplet.mail-server.*.ipv4_address[count.index]}"
    user = "root"
    identityfile = "${path.root}/data/ssh_keys/${digitalocean_droplet.mail-server.*.ipv4_address[count.index]}"
  }

}

resource "null_resource" "gen_ssh_config" {

  count = "${var.counter}"

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
