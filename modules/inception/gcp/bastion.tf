#
# Inception Bastion VM
#

resource "google_compute_instance" "bastion" {
  name         = "${var.vpc_name}-bastion"
  machine_type = "${var.bastion_instance_type}"
  zone         = "${data.google_compute_zones.available.names[0]}"

  allow_stopping_for_update = true

  tags = [
    "bastion-vpn",
    "bastion-ssh",
    "bastion-proxy",
  ]

  boot_disk {
    initialize_params {
      image = "${data.google_compute_image.bastion.self_link}"
      size  = "160"
    }
  }

  network_interface {
    subnetwork = "${var.dmz_subnetwork}"
    address    = "${google_compute_address.bastion-dmz.address}"

    access_config = [{
      nat_ip = "${google_compute_address.bastion-public.address}"
    }]
  }

  network_interface {
    subnetwork = "${var.engineering_subnetwork}"
    address    = "${google_compute_address.bastion-engineering.address}"
  }

  metadata {
    ssh-keys           = "ubuntu:${module.config.bastion_openssh_public_key} ubuntu"
    user-data          = "${module.config.bastion_cloud_init_config}"
    user-data-encoding = "base64"
  }
}

#
# Image
#

data "google_compute_image" "bastion" {
  name = "${var.bastion_image_name}"
}

#
# Networking
#

resource "google_compute_address" "bastion-dmz" {
  name         = "${var.vpc_name}-bastion-dmz"
  address_type = "INTERNAL"

  subnetwork = "${var.dmz_subnetwork}"
  address    = "${cidrhost(var.dmz_subnetwork_cidr, -3)}"
}

resource "google_compute_address" "bastion-engineering" {
  name         = "${var.vpc_name}-bastion-engineering"
  address_type = "INTERNAL"

  subnetwork = "${var.engineering_subnetwork}"
  address    = "${cidrhost(var.engineering_subnetwork_cidr, -3)}"
}

resource "google_compute_address" "bastion-public" {
  name         = "${var.vpc_name}-bastion"
  address_type = "EXTERNAL"
}

#
# Security (Firewall rules for the inception bastion instance)
#

resource "google_compute_firewall" "bastion-vpn" {
  name    = "${var.vpc_name}-bastion-vpn"
  network = "${var.dmz_network}"

  direction = "INGRESS"

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }

  allow {
    protocol = "${var.vpn_protocol}"
    ports    = ["${var.vpn_server_port}"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["bastion-vpn"]
}

resource "google_compute_firewall" "bastion-ssh" {
  name = "${var.vpc_name}-bastion-ssh"

  network   = "${var.engineering_network}"
  direction = "INGRESS"

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["${var.vpn_network}"]
  target_tags   = ["bastion-ssh"]
}

resource "google_compute_firewall" "bastion-proxy" {
  name    = "${var.vpc_name}-bastion-proxy"
  network = "${var.engineering_network}"

  direction = "INGRESS"

  allow {
    protocol = "tcp"
    ports    = ["${var.squidproxy_server_port}"]
  }

  source_ranges = ["${var.vpn_network}", "${var.vpc_cidr}"]
  target_tags   = ["bastion-proxy"]
}