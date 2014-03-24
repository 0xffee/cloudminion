class cloudminion::cm_agent(
   $cm_install_dir = '',
   $cm_conf_dir = "${cm_install_dir}/conf",
   $cm_bin_dir = "${cm_install_dir}/bin",
   $cm_lib_dir = "${cm_install_dir}/lib",
) {

    schedule { 'once': 
        range => "1 - 2",
        period => daily,
        repeat => 1,
    }

    file {'cm_install_dir':
        path => "$cm_install_dir",
        ensure  => directory,
        owner   => 'root',
        group   => 'root',
        mode    => '0755',
    }
    file {'cm_conf_dir':
        path => "$cm_conf_dir",
        ensure  => directory,
        owner   => 'root',
        group   => 'root',
        mode    => '0755',
        require => [ File['cm_install_dir']],
    }
    file {'cm_bin_dir':
        path => "$cm_bin_dir",
        ensure  => directory,
        owner   => 'root',
        group   => 'root',
        mode    => '0755',
        require => [ File['cm_install_dir']],
    }
    file {'cm_lib_dir':
        path => "$cm_lib_dir",
        ensure  => directory,
        owner   => 'root',
        group   => 'root',
        mode    => '0755',
        require => [ File['cm_install_dir']],
    }

    file {"cm_agent.cfg":
        path => "${cm_conf_dir}/cm_agent.cfg",
        owner => 'root',
        group => 'root',
        content => template("cloudminion/cm_agent.cfg.erb"),
        ensure => file,
        mode => '0664',
        require => [ File['cm_conf_dir']],
    }

    file {"Rules.pm":
        path => "${cm_conf_dir}/Rules.pm",
        owner => 'root',
        group => 'root',
        content => template("cloudminion/Rules.pm.erb"),
        ensure => file,
        mode => '0664',
        require => [ File['cm_conf_dir']],
    }

    file {"cm_agent.pl":
        path => "${cm_bin_dir}/cm_agent.pl",
        owner => 'root',
        group => 'root',
        source => 'puppet:///modules/cloudminion/cm_agent.pl',
        ensure => file,
        mode => '0755',
        require => [ File['cm_bin_dir']],
    }

    exec {"run_cm_agent":
        command => "$cm_bin_dir/cm_agent.pl",
        timeout => 30,
        schedule => "once",
        require => [ File['cm_agent.pl']],
    }     

}

