# Test whether a given class or definition is defined
Puppet::Parser::Functions::newfunction(:declared, :type => :rvalue, :doc => "Determine whether
  a given resource is declared. Returns true or false. Accepts resource references.

  The `declared` function checks both native and defined types, including types
  provided as plugins via modules. Resource declarations are checked using resource
  references, e.g. `defined( File['/tmp/myfile'] )`. Checking whether a given resource
  has been declared is, unfortunately, dependent on the parse order of
  the configuration, and the following code will not work:

      if defined(File['/tmp/foo']) {
          notify(\"This configuration includes the /tmp/foo file.\")
      }
      file {\"/tmp/foo\":
          ensure => present,
      }

  However, this order requirement refers to parse order only, and ordering of
  resources in the configuration graph (e.g. with `before` or `require`) does not
  affect the behavior of `defined`.") do |vals|
    result = false
    vals = [vals] unless vals.is_a?(Array)
    vals.each do |val|
      case val
      when Puppet::Resource
        if findresource(val.to_s)
          result = true
          break
        end
      else
        raise ArgumentError, "Invalid argument of type '#{val.class}' to 'declared'"
      end
    end
    result
end
