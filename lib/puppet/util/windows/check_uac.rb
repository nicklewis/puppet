require 'win32/registry'
include Win32

# When UAC is enabled, local administrator accounts run as normal user. So many 
# mutable o/s calls will fail, usually with 'access denied'. Try to detect if user 
# is in 'Administrators' group, but UAC is enabled. 

# TODO??: If true, raise security exception. 

# cst 071311: FIXME Incomplete. Only checks registry. Need to check current user 
# permissions as well.
#
# A good reference for howto is http://stackoverflow.com/questions/95510/how-to-detect-whether-vista-uac-is-enabled
# We would use the WIn32API gem to connect to the Shell32.DLL API funciton required.
#
# Also try:
# net localgroup administrators | find "%USERNAME%"
#
module PuppetWindows
	#
	# https://gist.github.com/65931
	#
	# Method to detect whether we are running from an elevated command-prompt
	# under Vista/Win7 or as part of the local Administrators group in WinXP.
	#
	def elevated?
		whoami = `whoami /groups` rescue nil
		if whoami =~ /S-1-16-12288/
			true
		else
			# cst FIXME: No backtick execs: insecure
			admin = `net localgroup administrators | find "%USERNAME%"` rescue ""
			admin.empty? ? false : true
		end
	end	


	def self.UACEnabled?
		# TODO: Read on this key will fail w/out elevated privs
		# reg query "HKU\S-1-5-19"
		bUacEnabled = 1	# assume UAC is enabled if not explicitly disabled
		Win32::Registry::HKEY_LOCAL_MACHINE.open('SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System') do |reg|
			bUacEnabled = reg['EnableLUA', Win32::Registry::REG_DWORD] || 1	
		#  	assert "REG_DWORD" == Win32::Registry.type2name(type)
		end
	rescue Exception => e
		puts "xxxx UACEnabled?: #{e}.chomp"
	ensure
		bUacEnabled
	end

	
end
