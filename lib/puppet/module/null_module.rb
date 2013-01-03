require 'puppet/module'

# We use the NullModule singleton when talking about the module a resource is
# in, in the case where a resource isn't actually in a module. For that reason,
# the environment doesn't actually matter, but we need to have one, so we use
# root, which will always exist and will always be the same.
class Puppet::Module::NullModule < Puppet::Module
  def self.instance
    @instance ||= new
  end

  def null_module?
    true
  end

  def version
    nil
  end

  def dependencies
    []
  end

  def match_manifests(path, cwd)
    glob = File.expand_path(path, cwd)
    # If they didn't give us an extension, we assume they want any kind of
    # manifest of that name, so we append our own file extensions.
    glob << '{.pp,.rb}' if File.extname(glob).empty?

    Dir.glob(glob).uniq.reject { |f| FileTest.directory?(f) }
  end

  # NullModule doesn't have templates, or plugins, etc.
  Puppet::Module::FILETYPES.each do |filetype, path|
    define_method(filetype.chomp('s')) do |file|
      nil
    end
  end

  private

  def initialize
    super('null', nil, Puppet::Node::Environment.root)
  end
end
