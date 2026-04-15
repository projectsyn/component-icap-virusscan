local kap = import 'lib/kapitan.libjsonnet';
local inv = kap.inventory();
local params = inv.parameters.icap_virusscan;

local sanitizedContainer(container) = (container
                                       { [if params.test then 'image']: 'escaped/image' });
{ sanitizedContainer: sanitizedContainer }
