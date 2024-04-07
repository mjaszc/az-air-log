# Local container image
locals {
  image_name = "az-air-log"
  image_tag  = "latest"
}

# Create a docker image
resource "null_resource" "docker_image" {
  triggers = {
    image_name         = local.image_name
    image_tag          = local.image_tag
    registry_name      = "${azurerm_container_registry.airlog-acr.name}"
    dockerfile_path    = "../app/Dockerfile"
    dockerfile_context = "../app"
    # Trigger the build when the Dockerfile or any file in the app directory changes
    dir_sha1           = sha1(join("", [for f in fileset("../", "../app/*") : filesha1(f)]))
  }

  provisioner "local-exec" {
    command     = "./scripts/build_acr.sh ${self.triggers.image_name} ${self.triggers.image_tag} ${self.triggers.registry_name} ${self.triggers.dockerfile_path} ${self.triggers.dockerfile_context}"
    interpreter = ["bash", "-c"]
  }

  depends_on = [
    azurerm_container_registry.airlog-acr
  ]
}