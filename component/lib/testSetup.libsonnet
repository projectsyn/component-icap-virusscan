local kap = import 'lib/kapitan.libjsonnet';
local sanitizedContainerLib = import 'sanitizedContainer.libsonnet';
local sanitizedContainer = sanitizedContainerLib.sanitizedContainer;
local inv = kap.inventory();
local params = inv.parameters.icap_virusscan;

local nginxLabels = { app: 'nginx' };

local nginxConfigEntryName = 'default.conf';

local nginxConfigMap = {
  apiVersion: 'v1',
  kind: 'ConfigMap',
  metadata: {
    name: 'squid-nginx-configmap',
    namespace: params.namespace,
    labels: nginxLabels,
  },
  data: {
    [nginxConfigEntryName]: |||
      server {
        listen 8080;

        location / {
          return 200;
        }
      }
    |||,
  },
};

local nginxConfigMapVolume = {
  name: 'nginx-conf',
  configMap: {
    name: nginxConfigMap.metadata.name,
  },
};

local nginxDeploymentParams = params.deployments['squid-nginx'];

local sanitizedNginxDeploymentParams = {
  metadata: nginxDeploymentParams.metadata,
  spec: nginxDeploymentParams.spec,
};

local nginxDeployment = std.mergePatch({
  apiVersion: 'apps/v1',
  kind: 'Deployment',
  metadata: {
    name: 'nginx',
    namespace: params.namespace,
    labels: nginxLabels,
  },
  spec: {
    replicas: 1,
    selector: {
      matchLabels: nginxLabels,
    },
    template: {
      metadata: {
        labels: nginxLabels,
        annotations: {
            'checksum/config': std.sha256(std.manifestJsonMinified(nginxConfigMap))
        }
      },
      spec: {
        containers: [
          std.mergePatch({
            name: 'nginx',
            ports: [
              { name: 'http', containerPort: 8080 },
            ],
            volumeMounts: [
              {
                mountPath: '/etc/nginx/conf.d/default.conf',
                name: nginxConfigMapVolume.name,
                subPath: nginxConfigEntryName,
              },
            ],
          }, sanitizedContainer(nginxDeploymentParams.container_nginx)),
        ],

        volumes: [
          nginxConfigMapVolume,
        ],
      },
    },
  },
}, sanitizedNginxDeploymentParams);

local nginxService = {
  apiVersion: 'v1',
  kind: 'Service',
  metadata: {
    name: 'nginx-return-200',
    namespace: params.namespace,
    labels: nginxLabels,
  },
  spec: {
    type: 'ClusterIP',
    selector: nginxLabels,
    ports: [
      {
        name: 'nginx',
        port: 80,
        targetPort: 'http',
        protocol: 'TCP',
      },
    ],
  },
};

local selectorLabels = { app: 'squid' };

local deploymentParams = params.deployments.squid;

local sanitizedDeploymentParams = {
  metadata: deploymentParams.metadata,
  spec: deploymentParams.spec,
};

local deployment = std.mergePatch({
  apiVersion: 'apps/v1',
  kind: 'Deployment',
  metadata: {
    name: 'squid',
    namespace: params.namespace,
    labels: selectorLabels,
  },
  spec: {
    replicas: 1,
    selector: {
      matchLabels: selectorLabels,
    },
    template: {
      metadata: {
        labels: selectorLabels,
      },
      spec: {
        containers: [
          std.mergePatch({
            name: 'squid',
            ports: [ { name: 'http', containerPort: 3128 } ],
            env: [
                {
                    name: 'ICAP_SERVICE_CONFIG',
                    value: |||
                             icap_service service_avi_1 reqmod_precache icap://icap.%s.svc.cluster.local:80/squidclamav bypass=on on-overload=bypass
                             adaptation_service_set avi service_avi_1
                             adaptation_access avi allow all
                           ||| % [ params.namespace ],
                },
                {
                  name: 'UPSTREAM_HOST',
                  value: '%s.%s.svc.cluster.local' % [ nginxService.metadata.name, nginxService.metadata.namespace ],
                }
            ]
          }, sanitizedContainer(deploymentParams.container_squid)),
        ],
      },
    },
  },
}, sanitizedDeploymentParams);

local service = {
  apiVersion: 'v1',
  kind: 'Service',
  metadata: {
    name: 'squid',
    namespace: params.namespace,
    labels: selectorLabels,
  },
  spec: {
    type: 'ClusterIP',
    selector: selectorLabels,
    ports: [
      {
        name: 'squid',
        port: 80,
        targetPort: 'http',
        protocol: 'TCP',
      },
    ],
  },
};

local httpRoute = {
  apiVersion: 'gateway.networking.k8s.io/v1',
  kind: 'HTTPRoute',
  metadata: {
    name: 'squid-httproute',
    namespace: params.httproute.gatewayNamespace,
  },
  spec: {
    hostnames: [ params.squid_domain ],
    parentRefs: [
      {
        group: 'gateway.networking.k8s.io',
        kind: 'Gateway',
        name: params.httproute.gatewayName,
        namespace: params.httproute.gatewayNamespace,
        sectionName: params.httproute.sectionName,
      },
    ],
    rules: [
      {
        matches: [
          {
            path: {
              type: 'PathPrefix',
              value: '/',
            },
          },
        ],
        backendRefs: [
          {
            group: '',
            kind: 'Service',
            name: service.metadata.name,
            namespace: params.namespace,
            port: 80,
            weight: 1,
          },
        ],
        timeouts: {
          backendRequest: '0s',
        },
      },
    ],
  },
};

local referenceGrant = {
  apiVersion: 'gateway.networking.k8s.io/v1beta1',
  kind: 'ReferenceGrant',
  metadata: {
    name: 'allow-squid-service',
    namespace: params.namespace,
  },
  spec: {
    from: [
      {
        group: 'gateway.networking.k8s.io',
        kind: 'HTTPRoute',
        namespace: params.httproute.gatewayNamespace,
      },
    ],
    to: [
      {
        group: '',
        kind: 'Service',
        name: service.metadata.name,
      },
    ],
  },
};

local ingressNetworkPolicy = {
  apiVersion: 'networking.k8s.io/v1',
  kind: 'NetworkPolicy',
  metadata: {
    name: 'squid-allow-gateway',
    namespace: params.namespace,
  },
  spec: {
    podSelector: {
      matchLabels: selectorLabels,
    },
    policyTypes: [ 'Ingress' ],
    ingress: [
      {
        from: [
          {
            namespaceSelector: {
              matchLabels: {
                'kubernetes.io/metadata.name': params.httproute.gatewayNamespace,
              },
            },
          },
        ],
      },
    ],
  },
};

local egressNetworkPolicy = {
  apiVersion: 'networking.k8s.io/v1',
  kind: 'NetworkPolicy',
  metadata: {
    name: 'allow-%s' % params.namespace,
    namespace: params.httproute.gatewayNamespace,
  },
  spec: {
    podSelector: {
      matchLabels: {
        'gateway.networking.k8s.io/gateway-class-name': params.httproute.gatewayClassName,
        'gateway.networking.k8s.io/gateway-name': params.httproute.gatewayName,
      },
    },
    policyTypes: [ 'Egress' ],
    egress: [
      {
        to: [
          {
            namespaceSelector: {
              matchLabels: {
                'kubernetes.io/metadata.name': params.namespace,
              },
            },
          },
        ],
      },
    ],
  },
};

local hasHttpRoute = std.isString(params.squid_domain) && params.httproute.enabled;

local squidManifests = {
  '50_squid-deployment': deployment,
  '51_squid-service': service,
  [if hasHttpRoute then '52_squid-httproute']: httpRoute,
  [if hasHttpRoute then '53_squid-ingressNetworkPolicy']: ingressNetworkPolicy,
  '54_squid-nginx-configMap': nginxConfigMap,
  '55_squid-nginx-deployment': nginxDeployment,
  '56_squid-nginx-service': nginxService,
  [if hasHttpRoute then '57_squid-referenceGrant']: referenceGrant,
  [if hasHttpRoute then '58_squid-egressNetworkPolicy']: egressNetworkPolicy,
};

if params.enable_squid then squidManifests else {}
