provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# VPC
resource "google_compute_network" "vpc_network" {
  name                    = "gitops-portfolio-vpc"
  auto_create_subnetworks = false
}

# Subnet
resource "google_compute_subnetwork" "subnet" {
  name          = "gitops-portfolio-subnet"
  ip_cidr_range = "10.0.0.0/24"
  region        = var.region
  network       = google_compute_network.vpc_network.id
}

# Firewall rules
resource "google_compute_firewall" "allow_ssh" {
  name    = "allow-ssh"
  network = google_compute_network.vpc_network.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]
}

resource "google_compute_firewall" "allow_internal" {
  name    = "allow-internal"
  network = google_compute_network.vpc_network.name

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }
  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }
  allow {
    protocol = "icmp"
  }

  source_ranges = ["10.0.0.0/24"]
}

resource "google_compute_firewall" "allow_vpn" {
  name    = "allow-vpn"
  network = google_compute_network.vpc_network.name

  allow {
    protocol = "udp"
    ports    = ["1194"]
  }

  source_ranges = ["0.0.0.0/0"]
}

resource "google_compute_firewall" "allow_http_https" {
  name    = "allow-http-https"
  network = google_compute_network.vpc_network.name

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["gitlab", "jenkins", "monitoring", "postfix"]
}


# Règle pour Jenkins (port 8080)
resource "google_compute_firewall" "allow_jenkins" {
  name    = "allow-jenkins"
  network = google_compute_network.vpc_network.name

  allow {
    protocol = "tcp"
    ports    = ["8080"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["jenkins"]
}

# Règle pour Monitoring (Grafana, Prometheus, etc.)
resource "google_compute_firewall" "allow_monitoring" {
  name    = "allow-monitoring"
  network = google_compute_network.vpc_network.name

  allow {
    protocol = "tcp"
    ports    = ["3000", "9090", "9093", "9100", "8080"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["monitoring"]
}

# VM instances
# OpenVPN VM
resource "google_compute_instance" "openvpn" {
  name         = "openvpn"
  machine_type = "e2-small"
  tags         = ["openvpn"]

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
      size  = 20
    }
  }

  network_interface {
    network    = google_compute_network.vpc_network.name
    subnetwork = google_compute_subnetwork.subnet.name
    access_config {
      // Ephemeral public IP
    }
  }

  metadata = {
    ssh-keys = "${var.ssh_user}:${file(var.ssh_pub_key_file)}"
  }
}

# Jenkins VM
resource "google_compute_instance" "jenkins" {
  name         = "jenkins"
  machine_type = "e2-medium"
  tags         = ["jenkins"]

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
      size  = 30
    }
  }

  network_interface {
    network    = google_compute_network.vpc_network.name
    subnetwork = google_compute_subnetwork.subnet.name
    access_config {
      // Ephemeral public IP
    }
  }

  metadata = {
    ssh-keys = "${var.ssh_user}:${file(var.ssh_pub_key_file)}"
  }
}

# GitLab VM
resource "google_compute_instance" "gitlab" {
  name         = "gitlab"
  machine_type = "e2-standard-2"
  tags         = ["gitlab"]

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
      size  = 50
    }
  }

  network_interface {
    network    = google_compute_network.vpc_network.name
    subnetwork = google_compute_subnetwork.subnet.name
    access_config {
      // Ephemeral public IP
    }
  }

  metadata = {
    ssh-keys = "${var.ssh_user}:${file(var.ssh_pub_key_file)}"
  }
}

# Postfix VM with PostgreSQL
resource "google_compute_instance" "postfix" {
  name         = "postfix"
  machine_type = "e2-medium"
  tags         = ["postfix"]

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
      size  = 30
    }
  }

  network_interface {
    network    = google_compute_network.vpc_network.name
    subnetwork = google_compute_subnetwork.subnet.name
    access_config {
      // Ephemeral public IP
    }
  }

  metadata = {
    ssh-keys = "${var.ssh_user}:${file(var.ssh_pub_key_file)}"
  }
}

# Monitoring VM
resource "google_compute_instance" "monitoring" {
  name         = "monitoring"
  machine_type = "e2-medium"
  tags         = ["monitoring"]

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
      size  = 30
    }
  }

  network_interface {
    network    = google_compute_network.vpc_network.name
    subnetwork = google_compute_subnetwork.subnet.name
    access_config {
      // Ephemeral public IP
    }
  }

  metadata = {
    ssh-keys = "${var.ssh_user}:${file(var.ssh_pub_key_file)}"
  }
}

# Create volume for persistent data
resource "google_compute_disk" "gitlab_data" {
  name = "gitlab-data"
  type = "pd-ssd"
  size = 100
  zone = var.zone
}

resource "google_compute_attached_disk" "gitlab_data_attachment" {
  disk     = google_compute_disk.gitlab_data.id
  instance = google_compute_instance.gitlab.id
}

resource "google_compute_disk" "postfix_data" {
  name = "postfix-data"
  type = "pd-standard"
  size = 50
  zone = var.zone
}

resource "google_compute_attached_disk" "postfix_data_attachment" {
  disk     = google_compute_disk.postfix_data.id
  instance = google_compute_instance.postfix.id
}

resource "google_compute_disk" "monitoring_data" {
  name = "monitoring-data"
  type = "pd-standard"
  size = 100
  zone = var.zone
}

resource "google_compute_attached_disk" "monitoring_data_attachment" {
  disk     = google_compute_disk.monitoring_data.id
  instance = google_compute_instance.monitoring.id
}

# Output
output "openvpn_ip" {
  value = google_compute_instance.openvpn.network_interface[0].access_config[0].nat_ip
}

output "jenkins_ip" {
  value = google_compute_instance.jenkins.network_interface[0].access_config[0].nat_ip
}

output "gitlab_ip" {
  value = google_compute_instance.gitlab.network_interface[0].access_config[0].nat_ip
}

output "postfix_ip" {
  value = google_compute_instance.postfix.network_interface[0].access_config[0].nat_ip
}

output "monitoring_ip" {
  value = google_compute_instance.monitoring.network_interface[0].access_config[0].nat_ip
}
