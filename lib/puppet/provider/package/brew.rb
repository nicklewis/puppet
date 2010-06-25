require 'puppet/provider/package'
require 'uri'

Puppet::Type.type(:package).provide :brew, :parent => Puppet::Provider::Package do
    desc "Ruby Homebrew support."

    commands :brewcmd => "brew"

    def install
        command = [command(:brewcmd), "install"]
        command << resource[:name]
        output = execute(command)
        unless $? == 0
            self.fail "Could not install: %s" % output.chomp
        end
    end

    def uninstall
        command = [command(:brewcmd), "uninstall"]
        command << resource[:name]
        output = execute(command)
        unless $? == 0
            self.fail "Could not uninstall: %s" % output.chomp
        end
    end

    def update
        command = [command(:brewcmd), "update", resource[:name]]
        output = execute(command)
        unless $? == 0
            self.fail "Could not update: %s" % output.chomp
        end
    end

    def query
        not self.class.cellar.find { |keg| keg[:name] == resource[:name] }.nil?
    end

    def self.instances
        cellar.collect do |keg|
            new(keg)
        end
    end

    def self.cellar
        command = [command(:brewcmd), "list"]
        output = execute(command)
        unless $? == 0
            raise Puppet::Error.new "Could not list packages: %s" % output.chomp
        end
        output.split.collect do |keg|
            { :name => keg, :ensure => :present, :provider => :brew }
        end
    end
end
