// main template for icap-virusscan
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local inv = kap.inventory();
// The hiera parameters for the component
local params = inv.parameters.icap_virusscan;

local instance = inv.parameters._instance;

local clamavConfigMapName = 'clamav';
local cIcapConfigMapName = 'c-icap';

local selectorLabels = {
  app: 'clamav-icap',
  instance: instance,
};

local namespace = kube.Namespace(params.namespace) {
  metadata+: {
    labels+: params.namespaceLabels,
    annotations+: params.namespaceAnnotations,
  },
};

local clamavConfigMap = {
  apiVersion: 'v1',
  kind: 'ConfigMap',
  metadata: {
    name: clamavConfigMapName,
    namespace: params.namespace,
    labels: selectorLabels,
  },
  data: {
    [key]: params.env.clamav[key]
    for key in std.objectFields(params.env.clamav)
  },
};

local cIcapConfigMap = {
  apiVersion: 'v1',
  kind: 'ConfigMap',
  metadata: {
    name: cIcapConfigMapName,
    namespace: params.namespace,
    labels: selectorLabels,
  },
  data: {
    [key]: params.env['c-icap'][key]
    for key in std.objectFields(params.env['c-icap'])
  },
};

local deploymentParams = params.deployments['clamav-icap'];

local sanitizedDeploymentParams = {
  metadata: deploymentParams.metadata,
  spec: deploymentParams.spec,
};

local deployment = std.mergePatch({
  apiVersion: 'apps/v1',
  kind: 'Deployment',
  metadata: {
    name: 'clamav-icap',
    namespace: params.namespace,
    labels: selectorLabels,
  },
  spec: {
    replicas: params.replicas,
    selector: {
      matchLabels: selectorLabels,
    },
    template: {
      metadata: {
        labels: selectorLabels,
      },
      spec: {
        affinity: {
          podAntiAffinity: {
            preferredDuringSchedulingIgnoredDuringExecution: [
              {
                weight: 1,
                podAffinityTerm: {
                  labelSelector: {
                    matchLabels: selectorLabels,
                  },
                  topologyKey: 'kubernetes.io/hostname',
                },
              },
            ],
          },
        },
        containers: [
          std.mergePatch({
            name: 'clamav',
            ports: [ { name: 'clamav', containerPort: 3310 } ],
            envFrom: [
              {
                configMapRef: {
                  name: clamavConfigMapName,
                },
              },
            ],
          }, deploymentParams.container_clamav),
          std.mergePatch({
            name: 'c-icap',
            ports: [ { name: 'icap', containerPort: 1344 } ],
            envFrom: [
              {
                configMapRef: {
                  name: cIcapConfigMapName,
                },
              },
            ],
          }, deploymentParams.container_cicap),
        ],
      },
    },
  },
}, sanitizedDeploymentParams);

local service = {
  apiVersion: 'v1',
  kind: 'Service',
  metadata: {
    name: 'icap',
    namespace: params.namespace,
    labels: selectorLabels,
  },
  spec: {
    type: 'ClusterIP',
    selector: selectorLabels,
    ports: [
      {
        name: 'icap',
        port: 80,
        targetPort: 'icap',
        protocol: 'TCP',
      },
    ],
  },
};

{
  [if params.createNamespace then '00_namespace']: namespace,
  '01_clamavConfigMap': clamavConfigMap,
  '02_cicapConfigMap': cIcapConfigMap,
  '03_deployment': deployment,
  '04_service': service,
} + (import 'lib/testSetup.libsonnet')
+ (import 'lib/debug.libsonnet')
