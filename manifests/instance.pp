# == Ressource type : memcached
#
# Manage multiple memcached instances
#
# == Parameters
# [* syslog *]
# Boolean.
# If true will pipe output to /bin/logger, sends to syslog.
#
define memcached::instance (
  Enum['present', 'latest', 'absent'] $package_ensure                                        = 'present',
  Boolean $service_manage                                                                    = true,
  String $service_name                                                                       = $name,
  Optional[Stdlib::Absolutepath] $logfile                                                    = "${::memcached::params::logpath}${service_name}",
  Boolean $logstdout                                                                         = false,
  Boolean $syslog                                                                            = false,
  Optional[Stdlib::Absolutepath] $pidfile                                                    = "/var/run/${name}.pid",
  Boolean $manage_firewall                                                                   = false,
  $max_memory                                                                                = '95%',
  Optional[Variant[Integer, String]] $max_item_size                                          = undef,
  Optional[Variant[Integer, String]] $min_item_size                                          = undef,
  Optional[Variant[Integer, String]] $factor                                                 = undef,
  Boolean $lock_memory                                                                       = false,
  Integer $tcp_port                                                                          = 11211,
  Integer $udp_port                                                                          = 11211,
  String $user                                                                               = $::memcached::params::user,
  Integer $max_connections                                                                   = 8192,
  Optional[String] $verbosity                                                                = undef,
  Optional[String] $unix_socket                                                              = undef,
  String $unix_socket_mask                                                                   = '0755',
  Boolean $install_dev                                                                       = false,
  Variant[String,Integer] $processorcount                                                    = $::processorcount,
  Boolean $service_restart                                                                   = true,
  Boolean $auto_removal                                                                      = false,
  Boolean $use_sasl                                                                          = false,
  Boolean $use_tls                                                                           = false,
  Optional[Stdlib::Absolutepath] $tls_cert_chain                                             = undef,
  Optional[Stdlib::Absolutepath] $tls_key                                                    = undef,
  Optional[Stdlib::Absolutepath] $tls_ca_cert                                                = undef,
  Optional[Integer] $tls_verify_mode                                                         = 1,
  Boolean $use_registry                                                                      = $::memcached::params::use_registry,
  String $registry_key                                                                       = 'HKLM\System\CurrentControlSet\services\memcached\ImagePath',
  Boolean $large_mem_pages                                                                   = false,
  Boolean $use_svcprop                                                                       = $::memcached::params::use_svcprop,
  String $svcprop_fmri                                                                       = 'memcached:default',
  String $svcprop_key                                                                        = 'memcached/options',
  Optional[Array[String]] $extended_opts                                                     = undef,
  String $config_file                                                                        = "${::memcached::params::config_path}${service_name}${::memcached::params::config_ext}",
  String $config_tmpl                                                                        = $::memcached::params::config_tmpl,
  Boolean $disable_cachedump                                                                 = false,
  Optional[Variant[Stdlib::Compat::Ip_address,Array[Stdlib::Compat::Ip_address]]] $listen_ip = '127.0.0.1'
) {
  if ! $::memcached::params::service_path {
    fail 'Multiple instances are not supported for this platform'
  }
  # Logging to syslog and file are mutually exclusive
  # Fail if both options are defined
  if $syslog and str2bool($logfile) {
    fail 'Define either syslog or logfile as logging destinations but not both.'
  }

  if $use_tls {
    if $tls_cert_chain == undef or $tls_key == undef {
      fail 'tls_cert_chain and tls_key should be set when use_tls is true.'
    }
  }

  if $package_ensure == 'absent' {
    $service_ensure = 'stopped'
    $service_enable = false
  } else {
    $service_ensure = 'running'
    $service_enable = true
  }

  # Handle if $listen_ip is not an array
  $real_listen_ip = [ $listen_ip ]

  ensure_resource('package', $memcached::params::package_name, {
    ensure   => $package_ensure,
    provider => $memcached::params::package_provider,
  })

  if $install_dev {
    ensure_resource('package', $memcached::params::dev_package_name, {
     ensure  => $package_ensure,
      require => Package[$memcached::params::package_name],
    })
  }

  if $manage_firewall {
    firewall { "100_tcp_${tcp_port}_for_memcached":
      dport  => $tcp_port,
      proto  => 'tcp',
      action => 'accept',
    }

    firewall { "100_udp_${udp_port}_for_memcached":
      dport  => $udp_port,
      proto  => 'udp',
      action => 'accept',
    }
  }

  if $service_restart and $service_manage {
    $service_notify_real = Service[$service_name]
  } else {
    $service_notify_real = undef
  }

  if ( $config_file ) {
    file { $config_file:
      owner   => 'root',
      group   => 0,
      mode    => '0644',
      content => template($config_tmpl),
      require => Package[$memcached::params::package_name],
      notify  => $service_notify_real,
    }
  }

  if $service_manage {
    $service_file = "${memcached::params::service_path}${service_name}.service"
    file { $service_file:
      owner   => 'root',
      group   => 0,
      mode    => '0644',
      content => template($::memcached::params::service_tmpl),
      require => Package[$memcached::params::package_name],
      notify  => $service_notify_real,
    }
    service { $service_name:
      ensure     => $service_ensure,
      enable     => $service_enable,
      hasrestart => true,
      hasstatus  => $memcached::params::service_hasstatus,
      require    => File[$service_file]
    }
  }

  if $use_registry {
    registry_value{ $registry_key:
      ensure => 'present',
      type   => 'string',
      data   => template($config_tmpl),
      notify => $service_notify_real,
    }
  }

  if $use_svcprop {
    svcprop { $svcprop_key:
      fmri     => $svcprop_fmri,
      property => $svcprop_key,
      value    => template($memcached::params::config_tmpl),
      notify   => $service_notify_real,
    }
  }
}
