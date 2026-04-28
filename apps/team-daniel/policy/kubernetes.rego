package main

import rego.v1

# Deny privileged containers
deny contains msg if {
  input.kind == "Deployment"
  container := input.spec.template.spec.containers[_]
  container.securityContext.privileged == true
  msg := sprintf("Container '%s' must not run as privileged", [container.name])
}

# Disallow hostNetwork
deny contains msg if {
  input.kind == "Deployment"
  input.spec.template.spec.hostNetwork == true
  msg := "Deployment must not use hostNetwork"
}
