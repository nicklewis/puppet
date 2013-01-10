require 'puppet/module'
require 'puppet/parser/parser'

# This is a silly central module for finding
# different kinds of files while parsing.  This code
# doesn't really belong in the Puppet::Module class,
# but it doesn't really belong anywhere else, either.
module Puppet::Parser::Files
  module_function

  # Return a list of manifests (as absolute filenames) that match +pat+
  # with the current directory set to +cwd+. If the first component of
  # +pat+ does not contain any wildcards and is an existing module, return
  # a list of manifests in that module matching the rest of +pat+
  # Otherwise, try to find manifests matching +pat+ relative to +cwd+
  def find_manifests(start, options = {})
    cwd = options[:cwd] || Dir.getwd
    module_name, pattern = split_file_path(start)
    mod = module_name ? Puppet::Node::Environment.new(options[:environment]).module(module_name) : Puppet::Module::NullModule.instance

    # If there isn't a module, we look for the whole original path
    pattern = start if mod.null_module?

    mod.match_manifests(pattern, cwd)
  end

  # Find the concrete file denoted by +file+. If +file+ is absolute,
  # return it directly. Otherwise try to find it as a template in a
  # module. If that fails, return it relative to the +templatedir+ config
  # param.
  # In all cases, an absolute path is returned, which does not
  # necessarily refer to an existing file
  def find_template(template, environment = nil)
    if template == File.expand_path(template)
      return template
    end

    if template_paths = templatepath(environment)
      # If we can find the template in :templatedir, we return that.
      template_paths.collect { |path|
        File::join(path, template)
      }.each do |f|
        return f if FileTest.exist?(f)
      end
    end

    # check in the default template dir, if there is one
    if td_file = find_template_in_module(template, environment)
      return td_file
    end

    nil
  end

  def find_template_in_module(template, environment = nil)
    path, file = split_file_path(template)

    # Because templates don't have an assumed template name, like manifests do,
    # we treat templates with no name as being templates in the main template
    # directory.
    return nil unless file

    Puppet::Node::Environment.new(environment).module(path).template(file)
  end

  # Return an array of paths by splitting the +templatedir+ config
  # parameter.
  def templatepath(environment = nil)
    dirs = Puppet.settings.value(:templatedir, environment).split(File::PATH_SEPARATOR)
    dirs.select do |p|
      File::directory?(p)
    end
  end

  # Split the path into the module and the rest of the path, or return
  # nil if the path is empty or absolute (starts with a /).
  # This method can return nil & anyone calling it needs to handle that.
  def split_file_path(path)
    if path.empty? or Puppet::Util.absolute_path?(path)
      [nil, path]
    else
      mod, relative_path = path.split(File::SEPARATOR, 2)
      relative_path ||= ''
      mod = nil if mod.empty?
      [mod, relative_path]
    end
  end
end
