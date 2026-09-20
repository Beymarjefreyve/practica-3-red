# outputs.tf
output "red" {
  value       = google_compute_network.vpc.name
  description = "Nombre de la VPC creada"
}

output "subred_publica" {
  value       = google_compute_subnetwork.publica.self_link
  description = "Identificador completo de la subred de aplicación"
}

output "ip_publica_app" {
  value       = google_compute_instance.app.network_interface[0].access_config[0].nat_ip
  description = "Dirección IP pública de la máquina de aplicación"
}

output "ip_interna_datos" {
  value       = google_compute_instance.datos.network_interface[0].network_ip
  description = "IP interna asignada a la máquina de datos privada"
}

output "subred_privada" {
  value       = google_compute_subnetwork.privada.self_link
  description = "Identificador completo de la subred de datos"
}

output "prueba_externa" {
  value       = "curl -m 8 http://${google_compute_instance.datos.network_interface[0].network_ip}:${var.puerto_datos}/"
  description = "Desde Cloud Shell debe agotar el tiempo"
}

output "prueba_interna" {
  value       = "gcloud compute ssh ${google_compute_instance.app.name} --zone ${var.zona} --tunnel-through-iap --command \"curl -s -m 5 http://${google_compute_instance.datos.network_interface[0].network_ip}:${var.puerto_datos}/\""
  description = "La consulta que si esta autorizada"
}

output "acceso_datos_por_iap" {
  value       = "gcloud compute ssh ${google_compute_instance.datos.name} --zone ${var.zona} --tunnel-through-iap"
  description = "Unica via de administracion de la maquina sin IP publica"
}