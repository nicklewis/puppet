require 'puppet/util/logging'
require 'semver'
require 'puppet/module_tool/applications'

# Support for modules
class Puppet::Module
  class Error < Puppet::Error; end
  class MissingModule < Error; end
  class IncompatibleModule < Error; end
  class UnsupportedPlatform < Error; end
  class IncompatiblePlatform < Error; end
  class MissingMetadata < Error; end
  class InvalidName < Error; end

  include Puppet::Util::Logging

  FILETYPES = {
    "manifests" => "manifests",
    "files" => "files",
    "templates" => "templates",
    "plugins" => "lib",
  }

  # Find and return the +module+ that +path+ belongs to. If +path+ is
  # absolute, or if there is no module whose name is the first component
  # of +path+, return +nil+
  def self.find(modname, environment = nil)
    Puppet.deprecation_warning "Puppet::Module.find is deprecated; please use Environment#module instead."
    return nil unless modname
    mod = Puppet::Node::Environment.new(environment).module(modname)
    # For backward compatibility, we return nil instead of NullModule
    mod.null_module? ? nil : mod
  end

  attr_reader :name, :environment, :path
  attr_writer :environment, :dependencies

  attr_accessor :forge_name
  attr_accessor :source, :author, :version, :license, :puppetversion, :summary, :description, :project_page

  def initialize(name, path, environment)
    @name = name
    @path = path
    @environment = environment

    assert_validity

    load_metadata if has_metadata?

    validate_puppet_version
  end

  def null_module?
    false
  end

  def has_metadata?
    return false unless metadata_file

    return false unless FileTest.exist?(metadata_file)

    metadata = PSON.parse File.read(metadata_file)


    return metadata.is_a?(Hash) && !metadata.keys.empty?
  end

  FILETYPES.each do |type, location|
    # A boolean method to let external callers determine if
    # we have files of a given type.
    define_method(type +'?') do
      type_subpath = subpath(location)
      unless FileTest.exist?(type_subpath)
        Puppet.debug("No #{type} found in subpath '#{type_subpath}' " +
                         "(file / directory does not exist)")
        return false
      end

      return true
    end

    # A method for returning a given file of a given type.
    # e.g., file = mod.manifest("my/manifest.pp")
    #
    # If the file name is nil, then the base directory for the
    # file type is passed; this is used for fileserving.
    define_method(type.sub(/s$/, '')) do |file|
      # If 'file' is nil then they're asking for the base path.
      # This is used for things like fileserving.
      if file
        full_path = File.join(subpath(location), file)
      else
        full_path = subpath(location)
      end

      return nil unless FileTest.exist?(full_path)
      return full_path
    end

    # Return the base directory for the given type
    define_method(type) do
      subpath(location)
    end
  end

  def license_file
    return @license_file if defined?(@license_file)

    return @license_file = nil unless path
    @license_file = File.join(path, "License")
  end

  def load_metadata
    data = PSON.parse File.read(metadata_file)
    @forge_name = data['name'].gsub('-', '/') if data['name']

    [:source, :author, :version, :license, :puppetversion, :dependencies].each do |attr|
      unless value = data[attr.to_s]
        unless attr == :puppetversion
          raise MissingMetadata, "No #{attr} module metadata provided for #{self.name}"
        end
      end

      # NOTICE: The fallback to `versionRequirement` is something we'd like to
      # not have to support, but we have a reasonable number of releases that
      # don't use `version_requirement`. When we can deprecate this, we should.
      if attr == :dependencies
        value.tap do |dependencies|
          dependencies.each do |dep|
            dep['version_requirement'] ||= dep['versionRequirement'] || '>= 0.0.0'
          end
        end
      end

      send(attr.to_s + "=", value)
    end
  end

  def dependencies
    @dependencies ||= []
  end

  # Return the list of manifests matching the given glob pattern,
  # defaulting to 'init.{pp,rb}' for empty modules.
  def match_manifests(rest, cwd=nil)
    pat = File.join(path, "manifests", rest || 'init')
    [manifest("init.pp"),manifest("init.rb")].compact + Dir.
      glob(pat + (File.extname(pat).empty? ? '.{pp,rb}' : '')).
      reject { |f| FileTest.directory?(f) }
  end

  def metadata_file
    return @metadata_file if defined?(@metadata_file)

    return @metadata_file = nil unless path
    @metadata_file = File.join(path, "metadata.json")
  end

  def modulepath
    File.dirname(path) if path
  end

  # Find all plugin directories.  This is used by the Plugins fileserving mount.
  def plugin_directory
    subpath("lib")
  end

  def to_s
    result = "Module #{name}"
    result += "(#{path})" if path
    result
  end

  def dependencies_as_modules
    dependencies.map do |dep|
      author, dep_name = dep["name"].split('/')
      environment.module(dep_name)
    end.reject(&:null_module?)
  end

  def required_by
    environment.module_requirements[self.forge_name] || {}
  end

  def has_local_changes?
    changes = Puppet::ModuleTool::Applications::Checksummer.run(path)
    !changes.empty?
  end

  def local_changes
    Puppet::ModuleTool::Applications::Checksummer.run(path)
  end

  # Identify and mark unmet dependencies.  A dependency will be marked unmet
  # for the following reasons:
  #
  #   * not installed and is thus considered missing
  #   * installed and does not meet the version requirements for this module
  #   * installed and doesn't use semantic versioning
  #
  # Returns a list of hashes representing the details of an unmet dependency.
  #
  # Example:
  #
  #   [
  #     {
  #       :reason => :missing,
  #       :name   => 'puppetlabs-mysql',
  #       :version_constraint => 'v0.0.1',
  #       :mod_details => {
  #         :installed_version => '0.0.1'
  #       }
  #       :parent => {
  #         :name    => 'puppetlabs-bacula',
  #         :version => 'v1.0.0'
  #       }
  #     }
  #   ]
  #
  def unmet_dependencies
    unmet_dependencies = []

    dependencies.each do |dependency|
      forge_name = dependency['name']
      version_string = dependency['version_requirement'] || '>= 0.0.0'

      dep_mod = environment.module_by_forge_name(forge_name)

      error_details = {
        :name => forge_name,
        :version_constraint => version_string.gsub(/^(?=\d)/, "v"),
        :parent => {
          :name => self.forge_name,
          :version => self.version.gsub(/^(?=\d)/, "v")
        },
        :mod_details => {
          :installed_version => dep_mod.version
        }
      }

      if dep_mod.null_module?
        error_details[:reason] = :missing
        unmet_dependencies << error_details
        next
      end

      if version_string
        begin
          required_version_semver_range = SemVer[version_string]
          actual_version_semver = SemVer.new(dep_mod.version)
        rescue ArgumentError
          error_details[:reason] = :non_semantic_version
          unmet_dependencies << error_details
          next
        end

        unless required_version_semver_range.include? actual_version_semver
          error_details[:reason] = :version_mismatch
          unmet_dependencies << error_details
          next
        end
      end
    end

    unmet_dependencies
  end

  def validate_puppet_version
    return unless puppetversion and puppetversion != Puppet.version
    raise IncompatibleModule, "Module #{self.name} is only compatible with Puppet version #{puppetversion}, not #{Puppet.version}"
  end

  def ==(other)
    self.name == other.name &&
    self.version == other.version &&
    self.path == other.path &&
    self.environment == other.environment
  end

  # Assume filename is an absolute path
  def contains_file?(filename)
    return false unless path
    parents = Pathname.new(filename).enum_for(:ascend)
    parents.any? { |parent| parent.to_s == path }
  end

  private

  def subpath(type)
    File.join(path, type)
  end

  def assert_validity
    raise InvalidName, "Invalid module name #{name}; module names must be alphanumeric (plus '-'), not '#{name}'" unless name =~ /^[-\w]+$/
  end
end

require 'puppet/module/null_module'
