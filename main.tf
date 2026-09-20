terraform {
  required_providers {
    google = { source = "hashicorp/google" }
  }
}

provider "google" {
  project = var.proyecto
  region  = var.region
}

# La VPC es global. En modo personalizado nace sin subredes.
resource "google_compute_network" "vpc" {
  name                    = "${var.prefijo}-vpc"
  auto_create_subnetworks = false
}

# La subred sí es regional, y es donde las máquinas toman su IP interna.
resource "google_compute_subnetwork" "publica" {
  name          = "${var.prefijo}-sub-publica"
  ip_cidr_range = var.cidr_publica
  region        = var.region
  network       = google_compute_network.vpc.id
}

# main.tf (añadir)
resource "google_compute_instance" "app" {
  name         = "${var.prefijo}-app"
  machine_type = var.tipo_maquina
  zone         = var.zona
  tags         = ["servidor-web"]

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
    }
  }

  network_interface {
    # la máquina debe quedar en tu subred, no en la default
    subnetwork = google_compute_subnetwork.publica.id
    # un bloque vacío aquí otorga una IP pública efímera
    access_config {}
  }

   metadata_startup_script = templatefile("${path.module}/arranque.sh", {
    ip_datos       = google_compute_instance.datos.network_interface[0].network_ip
    puerto_datos   = var.puerto_datos
    identificacion = var.identificacion
  })
}

# main.tf (añadir)
resource "google_compute_firewall" "app_http" {
  name    = "${var.prefijo}-permitir-http"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }

  source_ranges = ["0.0.0.0/0"] 
  target_tags   = ["servidor-web"]
}

resource "google_compute_firewall" "ssh_iap" {
  name    = "${var.prefijo}-permitir-ssh-iap"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  # 35.235.240.0/20 es el rango desde el que Google reenvía SSH
  # a través de IAP. Es el único origen autorizado para el 22.
  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["servidor-web", "servidor-datos"]
}

# 1. Subred Privada para Datos (rango 10.10.2.0/24)
resource "google_compute_subnetwork" "privada" {
  name          = "${var.prefijo}-sub-privada"
  ip_cidr_range = var.cidr_privada
  region        = var.region
  network       = google_compute_network.vpc.id
}

# 2. Cloud Router para soporte de NAT
resource "google_compute_router" "router" {
  name    = "${var.prefijo}-router"
  region  = var.region
  network = google_compute_network.vpc.id
}

# 3. Cloud NAT (salida a internet sin IP publica para la subred privada)
resource "google_compute_router_nat" "nat" {
  name                               = "${var.prefijo}-nat"
  router                             = google_compute_router.router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS" 

  subnetwork {
    name                    = google_compute_subnetwork.privada.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }
}

# 4. VM de Datos (sin access_config -> solo IP interna)
resource "google_compute_instance" "datos" {
  name         = "${var.prefijo}-datos"
  machine_type = var.tipo_maquina
  zone         = var.zona
  tags         = ["servidor-datos"]

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.privada.id
    # NOTA: Sin el bloque access_config {} para garantizar que no tenga IP publica
  }

  metadata_startup_script = templatefile("${path.module}/arranque_datos.sh", {
    puerto_datos = var.puerto_datos
  })

  depends_on = [google_compute_router_nat.nat]
}

# 5. Cortafuegos Interno: Permite trafico a la VM de datos UNICAMENTE desde la VM Web
resource "google_compute_firewall" "app_a_datos" {
  name    = "${var.prefijo}-permitir-app-a-datos"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = [tostring(var.puerto_datos)]
  }

  source_tags = ["servidor-web"]
  target_tags = ["servidor-datos"]
}