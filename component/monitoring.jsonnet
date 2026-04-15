// main template for icap-virusscan
local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local prometheus = import 'lib/prometheus.libsonnet';
local sanitizedContainerLib = import 'lib/sanitizedContainer.libsonnet';
local inv = kap.inventory();

{}
