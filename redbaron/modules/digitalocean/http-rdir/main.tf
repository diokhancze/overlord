resource "random_id" "server" {
  count       = var.counter
  byte_length = 4
}

resource "tls_private_key" "ssh" {
  count     = var.counter
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "digitalocean_ssh_key" "ssh_key" {
  count      = var.counter
  name       = "http-rdir-key-${random_id.server[count.index].hex}"
  public_key = tls_private_key.ssh[count.index].public_key_openssh
}

resource "digitalocean_droplet" "http-rdir" {
  count    = var.counter
  image    = "debian-9-x64"
  name     = "http-rdir-${random_id.server[count.index].hex}"
  region   = var.available_regions[element(var.regions, count.index)]
  ssh_keys = [digitalocean_ssh_key.ssh_key[count.index].id]
  size     = var.size

  provisioner "remote-exec" {
    inline = [
      "apt-get update",
      "apt-get install -y tmux socat apache2",
      "a2enmod rewrite proxy proxy_http ssl",
      "systemctl stop apache2",
      "tmux new -d \"socat TCP4-LISTEN:80,fork TCP4:${element(var.redirect_to, count.index)}:${var.http-port}\" ';' split \"socat TCP4-LISTEN:443,fork TCP4:${element(var.redirect_to, count.index)}:${var.https-port}\"",
    ]

    connection {
      host        = self.ipv4_address
      type        = "ssh"
      user        = "root"
      private_key = tls_private_key.ssh[count.index].private_key_pem
    }
  }

  provisioner "local-exec" {
    command = "echo \"${tls_private_key.ssh[count.index].private_key_pem}\" > ssh_keys/${self.ipv4_address} && echo \"${tls_private_key.ssh[count.index].public_key_openssh}\" > ssh_keys/${self.ipv4_address}.pub && chmod 600 ssh_keys/*"
  }

  provisioner "local-exec" {
    when    = destroy
    command = "rm ssh_keys/${self.ipv4_address}*"
  }
}

data "template_file" "ssh_config" {
  count = var.counter

  template = file("../../redbaron/data/templates/ssh_config.tpl")

  depends_on = [digitalocean_droplet.http-rdir]

  vars = {
    name         = "http_rdir_${digitalocean_droplet.http-rdir[count.index].ipv4_address}"
    hostname     = digitalocean_droplet.http-rdir[count.index].ipv4_address
    user         = "root"
    identityfile = "${abspath(path.root)}/ssh_keys/${digitalocean_droplet.http-rdir[count.index].ipv4_address}"
  }
}

resource "null_resource" "gen_ssh_config" {
  count = var.counter

  triggers = {
    template_rendered = data.template_file.ssh_config[count.index].rendered
  }

  provisioner "local-exec" {
    command = "echo '${data.template_file.ssh_config[count.index].rendered}' > ssh_configs/config_${random_id.server[count.index].hex}"
  }

  provisioner "local-exec" {
    when    = destroy
    command = "rm ssh_configs/config_${random_id.server[count.index].hex}"
  }
}

