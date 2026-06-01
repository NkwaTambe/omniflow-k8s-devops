prometheus:
  prometheusSpec:
    retention: ${retention}
    storageSpec:
      volumeClaimTemplate:
        spec:
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: ${storage_size}
    enableAdminAPI: false

grafana:
  adminPassword: admin
  defaultDashboardsTimezone: utc
  service:
    type: ClusterIP
  persistence:
    enabled: false

alertmanager:
  enabled: true
  alertmanagerSpec:
    storage:
      volumeClaimTemplate:
        spec:
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 5Gi

nodeExporter:
  enabled: true

kubeStateMetrics:
  enabled: true
