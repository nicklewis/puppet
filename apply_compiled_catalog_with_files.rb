#!/usr/bin/ruby

nodefile = ARGV.pop
nodefile =~ /(.*)\.compiled_catalog_with_files/
nodename = $1
`tar -xvPf #{nodefile}`
modulepath = File.open("#{nodename}.modulepath").readlines.first
Kernel.system("puppet apply #{ARGV.join(" ")} --apply #{nodename}.catalog.pson --modulepath #{modulepath}")
