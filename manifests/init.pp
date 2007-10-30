# ntp/manifests/init.pp - Classes for configuring NTP
# Copyright (C) 2007 David Schmitt <david@schmitt.edv-bus.at>
# See LICENSE for the full license granted to you.

modules_dir { "ntp": }
	
$ntp_base_dir = "/var/lib/puppet/modules/ntp"
$ntp_package = $lsbdistcodename ? { 'sarge' => 'ntp-server', default => 'ntp' }

class ntp {

	package {
		$ntp_package:
			ensure => installed,
			before => File["/etc/ntp.conf"]
	}

	$local_stratum = $ntp_local_stratum ? {
		'' => 13,
		default => $ntp_local_stratum,
	}

	config_file { "/etc/ntp.conf":
		content => template("ntp/ntp.conf"),
		require => Package[$ntp_package];
	}

	service{ $ntp_package:
		ensure => running,
		pattern => ntpd,
		subscribe => [ File["/etc/ntp.conf"], File["/etc/ntp.client.conf"], File["/etc/ntp.server.conf"] ],
	}

	# various files and directories used by this module
	file{
		"${ntp_base_dir}/munin_plugin":
			source => "puppet://$servername/ntp/ntp_",
			mode => 0755, owner => root, group => root;
	}

	$ntps = gsub(split($configured_ntp_servers, " "), "(.+)", "ntp_\\1")
	munin::plugin { $ntps:
		ensure => "munin_plugin",
		script_path => $ntp_base_dir
	}

	case $ntp_servers { 
		'': { # this is a client, connect to our own servers
			info ( "${fqdn} will act as ntp client" )
			# collect all our servers
			concatenated_file { "/etc/ntp.client.conf":
				dir => "/var/lib/puppet/modules/ntp/ntp.client.d",
			}

			# unused configs
			file { "/var/lib/puppet/modules/ntp/ntp.server.d": ensure => directory, }
			# provide dummy dependency for collected files
			exec { "concat_/var/lib/puppet/modules/ntp/ntp.server.d":
				command => "/bin/true",
				refreshonly => true,
			}
			config_file { "/etc/ntp.server.conf": content => "\n", }

		}
		default: { # this is a server, connect to the specified upstreams
			info ( "${fqdn} will act as ntp server using ${ntp_servers} as upstream" )
			ntp::upstream_server { $ntp_servers: }
			@@concatenated_file_part {
				# export this server for our own clients
				"server_${fqdn}":
					dir => "/var/lib/puppet/modules/ntp/ntp.client.d",
					content => "server ${fqdn} iburst\n",
					## TODO: activate this dependency when the bug is fixed
					#before => File["/etc/ntp.client.conf"]
					;
				# export this server for our other servers
				"peer_${fqdn}":
					dir => "/var/lib/puppet/modules/ntp/ntp.server.d",
					content => "peer ${fqdn} iburst\nrestrict ${fqdn} nomodify notrap\n",
					## TODO: activate this dependency when the bug is fixed
					#before => File["/etc/ntp.server.conf"]
					;
			}
			concatenated_file {"/etc/ntp.server.conf":
				dir => "/var/lib/puppet/modules/ntp/ntp.server.d",
			}
			file { "/var/lib/puppet/modules/ntp/ntp.client.d": ensure => directory, }
			# provide dummy dependency for collected files
			exec { "concat_/var/lib/puppet/modules/ntp/ntp.client.d":
				command => "/bin/true",
				refreshonly => true,
			}
			config_file { "/etc/ntp.client.conf": content => "\n", }

			nagios2::service { "check_ntp": }

		}
	}

	# collect all our configs
	File <<||>>


	# private
	define add_config($content, $type) {

		config_file { "/var/lib/puppet/modules/ntp/ntp.${type}.d/${name}":
			content => "$content\n",
			before => File["/etc/ntp.${type}.conf"],
		}

	}


	# public
	define upstream_server($server_options = 'iburst') {
		ntp::add_config { "server_${name}":
			content => "server ${name} ${server_options}",
			type => "server",
		}
		# This will need the ability to collect exported defines
		# currently this is worked around by reading /etc/ntp*conf via a fact
		# case $name { $fqdn: { debug ("${fqdn}: Ignoring get_time_from for self") } default: { munin_ntp { $name: } } }
	}

	# private
	# Installs a munin plugin and configures it for a given host
	define munin_plugin() {

		$name_with_underscores = gsub($name, "\\.", "_")

		# replace the "legacy" munin plugin with our own
		munin::plugin {
			"ntp_${name_with_underscores}": ensure => absent;
			"ntp_${name}":
				ensure => "munin_plugin",
				script_path => "/var/lib/puppet/modules/ntp"
				;
		}
	}

	#legacy
	file{"/etc/ntp.puppet.conf": ensure => absent, }

}

# include this class on hosts who collect files but do not have other ntp infrastructure
class ntp::none {
	exec {
		"concat_/var/lib/puppet/modules/ntp/ntp.client.d":
			command => "/bin/true",
			refreshonly => true;
		"concat_/var/lib/puppet/modules/ntp/ntp.server.d":
			command => "/bin/true",
			refreshonly => true,
	}
	# also provide dummy directories!
	modules_dir { ["ntp/ntp.server.d", "ntp/ntp.client.d"]: }
}
