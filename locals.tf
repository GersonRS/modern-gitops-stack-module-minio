locals {
  domain      = format("minio.%s", trimprefix("${var.subdomain}.${var.base_domain}", "."))
  domain_full = format("minio.%s.%s", trimprefix("${var.subdomain}.${var.cluster_name}", "."), var.base_domain)

  self_signed_cert = {
    extraVolumeMounts = [
      {
        name      = "certificate"
        mountPath = format("/etc/ssl/certs/%s", var.cluster_issuer == "letsencrypt-staging" ? "tls.crt" : "ca.crt")
        subPath   = var.cluster_issuer == "letsencrypt-staging" ? "tls.crt" : "ca.crt"
      },
    ]
    extraVolumes = [
      {
        name = "certificate"
        secret = {
          secretName = "minio-tls"
        }
      }
    ]
  }

  oidc_config = var.oidc != null ? merge(
    {
      oidc = {
        enabled      = true
        configUrl    = "${var.oidc.issuer_url}/.well-known/openid-configuration"
        clientId     = var.oidc.client_id
        clientSecret = var.oidc.client_secret
        claimName    = "policy"
        scopes       = "openid,profile,email"
        redirectUri  = format("https://%s/oauth_callback", local.domain_full)
        claimPrefix  = ""
        comment      = ""
      }
    },
    var.cluster_issuer != "letsencrypt-prod" ? local.self_signed_cert : null
  ) : null

  helm_values = [{
    minio = merge(
      {
        mode          = "distributed" ## other supported values are "standalone"
        drivesPerNode = 2
        replicas      = 1
        pools         = 2
        persistence = {
          size = "10Gi"
        }
        resources = {
          requests = {
            memory = "128Mi"
          }
        }
        consoleIngress = {
          enabled = true
          annotations = {
            "cert-manager.io/cluster-issuer"                   = "${var.cluster_issuer}"
            "traefik.ingress.kubernetes.io/router.entrypoints" = "websecure"
            "traefik.ingress.kubernetes.io/router.tls"         = "true"
          }
          hosts = [
            local.domain,
            local.domain_full,
          ]
          tls = [{
            secretName = "minio-tls"
            hosts = [
              local.domain,
              local.domain_full,
            ]
          }]
        }
        metrics = {
          serviceMonitor = {
            enabled = var.enable_service_monitor
          }
        }
        rootUser     = "root"
        rootPassword = random_password.minio_root_secretkey.result
        users        = var.config_minio.users
        buckets      = var.config_minio.buckets
        policies     = var.config_minio.policies
      },
      local.oidc_config
    )
  }]
}
