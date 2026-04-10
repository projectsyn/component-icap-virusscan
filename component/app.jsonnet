local kap = import 'lib/kapitan.libjsonnet';
local inv = kap.inventory();
local params = inv.parameters.icap_virusscan;
local argocd = import 'lib/argocd.libjsonnet';

local app = argocd.App('icap-virusscan', params.namespace);

local appPath =
  local project = std.get(std.get(app, 'spec', {}), 'project', 'syn');
  if project == 'syn' then 'apps' else 'apps-%s' % project;

{
  ['%s/icap-virusscan' % appPath]: app,
}
