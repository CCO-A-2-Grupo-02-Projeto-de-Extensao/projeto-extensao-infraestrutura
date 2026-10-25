resource "aws_ecr_repository" "arandu" {
  name         = var.ecr_repository_name
  force_delete = true
}

locals {
  ecr_registry       = split("/", aws_ecr_repository.arandu.repository_url)[0]
  backend_ecr_image  = "${aws_ecr_repository.arandu.repository_url}:backend"
  frontend_ecr_image = "${aws_ecr_repository.arandu.repository_url}:frontend"
}

resource "terraform_data" "ecr_sync" {
  triggers_replace = [aws_ecr_repository.arandu.repository_url]

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = <<-EOF
      set -e
      aws ecr get-login-password --region ${var.aws_region} | docker login --username AWS --password-stdin ${local.ecr_registry}
      for imagem in ${var.backend_docker_image} ${var.frontend_docker_image}; do
        docker pull -q "$imagem"
        docker tag "$imagem" "${aws_ecr_repository.arandu.repository_url}:$${imagem##*:}"
        docker push -q "${aws_ecr_repository.arandu.repository_url}:$${imagem##*:}"
      done
    EOF
  }
}
