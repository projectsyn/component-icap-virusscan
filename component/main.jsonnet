// main template for icap-virusscan
local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local prometheus = import 'lib/prometheus.libsonnet';
local sanitizedContainerLib = import 'lib/sanitizedContainer.libsonnet';
local inv = kap.inventory();
local sanitizedContainer = sanitizedContainerLib.sanitizedContainer;

// The hiera parameters for the component
local params = inv.parameters.icap_virusscan;

local instance = inv.parameters._instance;

local clamavConfigMapName = 'clamav';
local cIcapConfigMapName = 'c-icap';

local selectorLabels = {
  app: 'clamav-icap',
  instance: instance,
};

local namespace = (
  if params.monitoring.enabled && std.member(inv.applications, 'prometheus') then
    prometheus.RegisterNamespace(kube.Namespace(params.namespace))
  else if params.monitoring.enabled && inv.parameters.facts.distribution == 'openshift4' then
    kube.Namespace(params.namespace) {
      metadata+: {
        labels+: { 'openshift.io/cluster-monitoring': 'true' },
      },
    }
  else
    kube.Namespace(params.namespace)
) + {
  metadata+: {
    labels+: params.namespaceLabels,
    annotations+: params.namespaceAnnotations,
  },
};

local deploymentParams = params.deployments['clamav-icap'];

local sanitizedDeploymentParams = {
  metadata: deploymentParams.metadata,
  spec: deploymentParams.spec,
};

local cIcapContainerPort = { name: 'icap', containerPort: 1344 };

local deployment = std.mergePatch({
  apiVersion: 'apps/v1',
  kind: 'Deployment',
  metadata: {
    namespace: params.namespace,
    labels: selectorLabels,
  },
  spec: {
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
            name: 'clamav',
            ports: [ { name: 'clamav', containerPort: 3310 } ],
            env: [
              {
                name: key,
                value: '%s' % params.env.clamav[key],
              }
              for key in std.objectFields(params.env.clamav)
            ],
          }, sanitizedContainer(deploymentParams.container_clamav)),
          std.mergePatch({
            name: 'c-icap',
            ports: [ cIcapContainerPort ],
            env: [
              {
                name: key,
                value: '%s' % params.env['c-icap'][key],
              }
              for key in std.objectFields(params.env['c-icap'])
            ],
          }, sanitizedContainer(deploymentParams.container_cicap)),
        ],
      },
    },
  },
}, sanitizedDeploymentParams);

local deploymentWithStrictAntiAffinity = std.mergePatch(deployment, {
  metadata: {
    name: 'clamav-icap-strict-anti-affinity',
  },
  spec: {
    replicas: params.replicas,
    template: {
      spec: {
        affinity: {
          podAntiAffinity: {
            requiredDuringSchedulingIgnoredDuringExecution: [
              {
                labelSelector: {
                  matchLabels: selectorLabels,
                },
                topologyKey: 'kubernetes.io/hostname',
              },
            ],
          },
        },
      },
    },
  },
});

local deploymentWithOptionalAntiAffinity = std.mergePatch(deployment, {
  metadata: {
    name: 'clamav-icap-strict-optional-affinity',
  },
  spec: {
    replicas: params.replicasWithOptionalAntiAffinity,
    template: {
      spec: {
        affinity: {
          podAntiAffinity: {
            preferredDuringSchedulingIgnoredDuringExecution: [
              {
                weight: 50,
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
      },
    },
  },
});

local podDisruptionBudget = {
  apiVersion: 'policy/v1',
  kind: 'PodDisruptionBudget',
  metadata: {
    name: deploymentWithStrictAntiAffinity.metadata.name,
    namespace: params.namespace,
    labels: selectorLabels,
  },
  spec: {
    minAvailable: params.minAvailable,
    selector: {
      matchLabels: selectorLabels,
    },
    unhealthyPodEvictionPolicy: 'IfHealthyBudget',
  },
};

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

local hasNetworkPolicies = std.length(params.allowFromNamespaces) > 0;

local networkPolicies = {
  apiVersion: 'networking.k8s.io/v1',
  kind: 'NetworkPolicy',
  metadata: {
    name: 'allow-connection-to-cicap',
    namespace: params.namespace,
    labels: selectorLabels,
  },
  spec: {
    podSelector: {
      matchLabels: selectorLabels,
    },
    policyTypes: [ 'Ingress' ],
    ingress: [
      {
        from: [
          { namespaceSelector: ns }
          for ns in params.allowFromNamespaces
        ],
        ports: [
          {
            protocol: 'TCP',
            port: cIcapContainerPort.containerPort,
          },
        ],
      },
    ],
  },
};

local prometheusRule = {
  apiVersion: 'monitoring.coreos.com/v1',
  kind: 'PrometheusRule',
  metadata: {
    name: 'icap-rules',
    namespace: params.namespace,
    labels: selectorLabels,
  },
  spec: params.monitoring.prometheusRuleSpec,

};

{
  [if params.createNamespace then '00_namespace']: namespace,
  '01_deploymentWithStrictAntiAffinity': deploymentWithStrictAntiAffinity,
  '01_deploymentWithOptionalAntiAffinity': deploymentWithOptionalAntiAffinity,
  [if (params.replicas + params.replicasWithOptionalAntiAffinity) > 1 then '02_podDisruptionBudget']: podDisruptionBudget,
  '03_service': service,
  [if hasNetworkPolicies then '04_networkPolicies']: networkPolicies,
  [if params.monitoring.enabled then '05_prometheusRule']: prometheusRule,
} + (import 'lib/testSetup.libsonnet')
+ (import 'lib/debug.libsonnet')
