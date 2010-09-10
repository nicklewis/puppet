#!/usr/bin/ruby
require 'getoptlong'
opts = GetoptLong.new(
  [ '--node', '-n', GetoptLong::REQUIRED_ARGUMENT ]
)

node = nil
opts.each do |opt, arg|
  case opt
    when '--node'
      node = arg
  end
end

require 'puppet'

# This almost works, but doesn't get the facts from the yamldir, not sure why
#Puppet::Node.cache_class = :yaml
#Puppet::Node::Facts.terminus_class = :facter
#Puppet::Node::Facts.cache_class = :yaml
#
#begin
#  unless catalog = Puppet::Resource::Catalog.find(node)
#    raise "Could not compile catalog for #{node}"
#  end
#
#  paths = catalog.vertices.
#      select {|vertex| vertex.type == "File" and vertex[:source] =~ %r{puppet://}}.
#      map {|file_resource| Puppet::FileServing::Metadata.find(file_resource[:source])}. # this step should return nil where source doesn't exist
#      compact.
#      map {|filemetadata| filemetadata.path}
#
#rescue => detail
#  $stderr.puts detail
#  exit(30)
#end

# This was my first attempt to retrieve file paths from the catalog, but requires some parsing of
# the already compiled catalog that I'm not sure is reliable
compiled_catalog_pson_string = `puppet master --compile #{node}`
# strip notices and warnings http://projects.puppetlabs.com/issues/2527
compiled_catalog = compiled_catalog_pson_string.split("\n").reject {|line| line =~ /warning:|notice:/}

module_files = {}
compiled_catalog.each do |line|
  module_files[$1] = $2 if line =~ %r{source.*puppet:///modules/(\w+)/(\w+)}
end

paths = module_files.map do |module_name, file_name|
  "/etc/puppet/modules/#{module_name}/files/#{file_name}"
end

paths = paths.select {|path| File.exist?(path)}
require 'pp'
pp paths

catalog_file = File.new("#{node}.catalog.pson", "w")
catalog_file.write compiled_catalog
catalog_file.close

tarred_filename = "#{node}.compiled_catalog_with_files.tar.gz"
`tar -cPzf #{tarred_filename} #{catalog_file.path} #{paths.join(' ')}`
puts "Created #{tarred_filename} with the compiled catalog for node #{node} and the necessary files"

File.delete(catalog_file.path)
