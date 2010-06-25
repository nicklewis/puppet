require 'puppet/provider/package'
require 'uri'

Puppet::Type.type(:package).provide :brew, :parent => Puppet::Provider::Package do
    desc "Ruby Homebrew support."

    commands :brewcmd => "brew"

    def install
        command = [command(:brew), "install"]
        command << resource[:name]
        output = execute(command)
        unless $? == 0
            self.fail "Could not install: %s" % output.chomp
        end
    end

    def latest
        install(:version => "--HEAD")
    end

    def query

    end

    def uninstall
    end

    def update
        command = [command(:brew), "update", resource[:name]]
    end
end
