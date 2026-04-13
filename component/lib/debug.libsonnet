local kap = import 'lib/kapitan.libjsonnet';
local inv = kap.inventory();
local params = inv.parameters.icap_virusscan;

local instance = inv.parameters._instance;


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
    ||| % [ std.manifestYamlDoc(params, indent_array_in_object=false, quote_keys=false) ],
  },
};

{
  [if params.debug then '99_debug']: configMap,
}
