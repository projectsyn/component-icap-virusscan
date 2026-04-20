local kap = import 'lib/kapitan.libjsonnet';
local inv = kap.inventory();
local params = inv.parameters.icap_virusscan;

local sanitizedParams = std.mergePatch(
  params,
  {
    [if params.test then 'deployments']: {
      'clamav-icap': {
        container_cicap: {
          image: 'escaped/image',
        },
        container_clamav: {
          image: 'escaped/image',
        },
      },
      squid: {
        container_squid: {
          image: 'escaped/image',
        },
      },
      'squid-nginx': {
        container_nginx: {
          image: 'escaped/image',
        },
      },
    },
  }
);


local configMap = {
  apiVersion: 'v1',
  kind: 'ConfigMap',
  metadata: {
    name: 'debug-configmap',
    namespace: params.namespace,
  },
  data: {
    debug: |||
      %s
    ||| % [ std.manifestYamlDoc(sanitizedParams, indent_array_in_object=false, quote_keys=false) ],
  },
};

{
  [if params.debug then '99_debug']: configMap,
}
