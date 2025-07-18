/**
* Copyright 2024 Google LLC
*
* Licensed under the Apache License, Version 2.0 (the "License");
* you may not use this file except in compliance with the License.
* You may obtain a copy of the License at
*
*      http://www.apache.org/licenses/LICENSE-2.0
*
* Unless required by applicable law or agreed to in writing, software
* distributed under the License is distributed on an "AS IS" BASIS,
* WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
* See the License for the specific language governing permissions and
* limitations under the License.
*/

# [START gke_quickstart_autopilot_app]
data "google_client_config" "default" {}

provider "kubernetes" {
  host                   = "https://${google_container_cluster.default.endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(google_container_cluster.default.master_auth[0].cluster_ca_certificate)

  ignore_annotations = [
    "^autopilot\\.gke\\.io\\/.*",
    "^cloud\\.google\\.com\\/.*"
  ]
}

# Provide time for Service cleanup
resource "time_sleep" "wait_service_cleanup" {
  depends_on = [google_container_cluster.default]

  destroy_duration = "180s"
}
# [END gke_quickstart_autopilot_app]

# resource "google_compute_address" "ingress_ip" {
#   name         = "lb-external-ip"
#   address_type = "EXTERNAL"
#   ip_version   = "IPV4"
#   region       = "us-central1"
# }

resource "google_compute_global_address" "ingress_ip" {
  name = "lb-external-ip"
}

########################################
# RED deployment + service
########################################
resource "kubernetes_deployment_v1" "red" {
  metadata { name = "red-deployment" }
  spec {
    replicas = 2
    selector { match_labels = { app = "red" } }
    template {
      metadata { labels = { app = "red" } }
      spec {
        container {
          name  = "red"
          image = "hashicorp/http-echo"
          args  = ["-text=Hello from RED"]
          port { container_port = 5678 }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "red" {
  metadata { name = "red-service" }
  spec {
    selector = { app = "red" }
    port {
      name        = "http"
      port        = 80
      target_port = 5678
    }
    type = "ClusterIP"
  }

  depends_on = [time_sleep.wait_service_cleanup]
}

########################################
# BLUE deployment + service
########################################
resource "kubernetes_deployment_v1" "blue" {
  metadata { name = "blue-deployment" }
  spec {
    replicas = 2
    selector { match_labels = { app = "blue" } }
    template {
      metadata { labels = { app = "blue" } }
      spec {
        container {
          name  = "blue"
          image = "hashicorp/http-echo"
          args  = ["-text=Hello from BLUE"]
          port { container_port = 5678 }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "blue" {
  metadata { name = "blue-service" }
  spec {
    selector = { app = "blue" }
    port {
      name        = "http"
      port        = 80
      target_port = 5678
    }
    type = "ClusterIP"
  }

  depends_on = [time_sleep.wait_service_cleanup]
}

########################################
# Ingress with path routing
########################################
resource "kubernetes_ingress_v1" "color_paths" {
  metadata {
    name = "color-paths"
    annotations = {
      "kubernetes.io/ingress.class"                 = "gce"
      "kubernetes.io/ingress.global-static-ip-name" = google_compute_global_address.ingress_ip.name
    }
  }

  spec {
    rule {
      http {
        path {
          path      = "/red"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service_v1.red.metadata[0].name
              port { number = 80 }
            }
          }
        }

        path {
          path      = "/blue"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service_v1.blue.metadata[0].name
              port { number = 80 }
            }
          }
        }
      }
    }
  }
}
