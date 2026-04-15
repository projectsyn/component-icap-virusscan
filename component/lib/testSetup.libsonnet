local kap = import 'lib/kapitan.libjsonnet';
local sanitizedContainerLib = import 'sanitizedContainer.libsonnet';
local sanitizedContainer = sanitizedContainerLib.sanitizedContainer;
local inv = kap.inventory();
local params = inv.parameters.icap_virusscan;

local instance = inv.parameters._instance;


local selectorLabels = { app: 'squid' };

local configMap = {
  apiVersion: 'v1',
  kind: 'ConfigMap',
  metadata: {
    name: 'squid-configmap',
    namespace: params.namespace,
    labels: selectorLabels,
  },
  data: {
    ICAP_SERVICE_CONFIG: |||
      icap_service service_avi_1 reqmod_precache icap://icap.%s.svc.cluster.local:80/squidclamav bypass=on on-overload=bypass
      adaptation_service_set avi service_avi_1
      adaptation_access avi allow all
    ||| % [ params.namespace ],
  },
};

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
            envFrom: [
              {
                configMapRef: {
                  name: configMap.metadata.name,
                },
              },
            ],
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

local ingress = {
  apiVersion: 'networking.k8s.io/v1',
  kind: 'Ingress',
  metadata: {
    annotations: {
      'route.openshift.io/insecureEdgeTerminationPolicy': 'Redirect',
      'route.openshift.io/termination': 'edge',
    },
    labels: {
      'app.hin-infra.ch/ingress-public': 'true',
    },
    name: 'squid-ingress',
    namespace: params.namespace,
  },
  spec: {
    ingressClassName: 'openshift-public',
    rules: [
      {
        host: params.squid_domain,
        http: {
          paths: [
            {
              backend: {
                service: {
                  name: 'squid',
                  port: {
                    number: 80,
                  },
                },
              },
              path: '/',
              pathType: 'Prefix',
            },
          ],
        },
      },
    ],
  },
};

local squidManifests = {
  '50_squid-configmap': configMap,
  '51_squid-deployment': deployment,
  '52_squid-service': service,
  [if std.isString(params.squid_domain) then '53_ingress']: ingress,
};

if params.enable_squid then squidManifests else {}
