terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
    }
  }
  required_version = ">= 0.13"
}

provider "yandex" {
  service_account_key_file = "key.json"
  cloud_id                 = "cloud_id"
  folder_id                = "folder_id"
  zone                     = "ru-central1-a"
}


resource "yandex_iam_service_account" "adminsrv" {
  name        = "adminsrv"
  description = "Service account for Kubernetes cluster"
}


resource "yandex_vpc_network" "vpc_net" {
  name = "vpc_name"
}

resource "yandex_vpc_subnet" "subnet_airflow" {
  v4_cidr_blocks = ["10.10.0.0/16"]
  network_id     = yandex_vpc_network.vpc_net.id
}

resource "yandex_vpc_subnet" "subnet_db" {
  v4_cidr_blocks = ["10.11.0.0/16"]
  network_id     = yandex_vpc_network.vpc_net.id
}

resource "yandex_vpc_subnet" "vpc_subnet" {
  v4_cidr_blocks = ["10.12.0.0/16"]
  network_id     = yandex_vpc_network.vpc_net.id
}

resource "yandex_compute_instance" "VM" {
  name        = "virtual_machine"
  platform_id = "standard-v3"

  resources {
    cores  = 2
    memory = 2
  }

  boot_disk {
    initialize_params{
      image_id = "fd800c7s2p483i648ifv"
    }
  }

  network_interface {
    index     = 1
    subnet_id = yandex_vpc_subnet.vpc_subnet.id
  }

  metadata = {
    ssh-keys = "ubuntu:${file("~/.ssh/id_ed25519.pub")}"
  }
}

resource "yandex_kubernetes_cluster" "zonal_cluster" {
  name        = "kubernetes-cluster"
  description = "description"

  network_id = yandex_vpc_network.vpc_net.id

  master {
    version = "1.30"
    zonal {
      zone      = yandex_vpc_subnet.subnet_airflow.zone
      subnet_id = yandex_vpc_subnet.subnet_airflow.id
    }

    public_ip = true


    maintenance_policy {
      auto_upgrade = true

      maintenance_window {
        start_time = "00:00"
        duration   = "23h"
      }
    }
  }

  labels = {
      environment = "production"
      project     = "airflow"
  }

  service_account_id      = yandex_iam_service_account.adminsrv.id
  node_service_account_id = yandex_iam_service_account.adminsrv.id


  release_channel         = "RAPID"
  network_policy_provider = "CALICO"

}

resource "yandex_kubernetes_node_group" "node_group" {
  cluster_id  = yandex_kubernetes_cluster.zonal_cluster.id
  name        = "node-group-1"

  instance_template {
    platform_id = "standard-v3"
    resources {
      cores  = 2
      memory = 4
    }
    boot_disk {
      type = "network-ssd"
      size = 64
    }
    network_interface {
      subnet_ids = [yandex_vpc_subnet.subnet_airflow.id]
      nat       = true
    }
  }

  scale_policy {
    fixed_scale {
      size = 1 
    }
  }
}

resource "yandex_mdb_postgresql_cluster" "airflow_db" {
  name        = "airflow-db"
  environment = "PRODUCTION"
  network_id  = yandex_vpc_network.vpc_net.id
  folder_id   = "folder_id"

  config {
    version = "15"
    resources {
      resource_preset_id = "s2.micro" 
      disk_size          = 10
      disk_type_id       = "network-ssd"
    }
  }

  host {
    zone      = "ru-central1-a"
    subnet_id = yandex_vpc_subnet.subnet_db.id
  }
}

resource "yandex_mdb_postgresql_user" "airflow_db_user" {
  cluster_id = yandex_mdb_postgresql_cluster.airflow_db.id
  name       = "airflow_user"
  password   = "airflow42"
  conn_limit = 50
  settings = {
    default_transaction_isolation = "read committed"
    log_min_duration_statement    = 5000
  }
}

resource "yandex_mdb_postgresql_database" "airflow_db_database" {
  cluster_id = yandex_mdb_postgresql_cluster.airflow_db.id
  name       = "airflow"
  owner      = yandex_mdb_postgresql_user.airflow_db_user.name
  lc_collate = "en_US.UTF-8"
  lc_type    = "en_US.UTF-8"
  extension {
    name = "uuid-ossp"
  }
  extension {
    name = "xml2"
  }
  depends_on = [yandex_mdb_postgresql_user.airflow_db_user]
}




