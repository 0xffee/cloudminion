class cloudminion::cm_sa(
   $cm_install_dir = '',
   $cm_conf_dir = "${cm_install_dir}/conf",
   $cm_bin_dir = "${cm_install_dir}/bin",
   $sa_cron_enabled = '',
) {

    file {"cm_sa.pl":
        path => "${cm_bin_dir}/cm_sa.pl",
        owner => 'root',
        group => 'root',
        source => 'puppet:///modules/cloudminion/cm_sa.pl',
        ensure => file,
        mode => '0775',
        require => [ File['cm_bin_dir']]
    }

    file {"cm_sar.pl":
        path => "${cm_bin_dir}/cm_sar.pl",
        owner => 'root',
        group => 'root',
        source => 'puppet:///modules/cloudminion/cm_sar.pl',
        ensure => file,
        mode => '0775',
        require => [ File['cm_bin_dir']]
    }
   
    if ($sa_cron_enabled == 'true' ) {
        cron { 'cron_cloudminion_sa':
            user  => 'root',
            hour   => '23',
            minute  => '59',
            command  => "${cm_bin_dir}/cm_sa.pl"
        }
    }



}

