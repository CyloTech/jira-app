#!/bin/bash
set -e

echo "**************************************************************"
echo "*                    Installing Postgres                     *"
echo "**************************************************************"

if [ ! -f /etc/postgres_installed ]; then
    if [ ! -f /var/lib/postgresql/data/postgresql.conf ]; then
        touch /etc/postgres_installed

        mkdir -p /home/appbox/config/postgresql
        mkdir -p /home/appbox/logs/postgresql

        source ${PG_APP_HOME}/functions.sh

        # default behaviour is to launch postgres
        map_uidgid

        create_datadir
        create_certdir
        create_logdir
        create_rundir

        set_resolvconf_perms

        configure_postgresql

        # Setup postgres Daemon
        echo "Setting up postgres daemon"
        mkdir -p /etc/service/postgres
cat << EOF >> /etc/service/postgres/run
#!/bin/bash
source \${PG_APP_HOME}/functions.sh

[[ \${DEBUG} == true ]] && set -x

# allow arguments to be passed to postgres
if [[ \${1:0:1} = '-' ]]; then
  EXTRA_ARGS="\$@"
  set --
elif [[ \${1} == postgres || \${1} == \$(which postgres) ]]; then
  EXTRA_ARGS="\${@:2}"
  set --
fi

exec start-stop-daemon --start --chuid \${PG_USER}:\${PG_USER} \
--exec \${PG_BINDIR}/postgres -- -D \${PG_DATADIR} \${EXTRA_ARGS}
EOF
        chmod +x /etc/service/postgres/run
    else
        echo "This is an update, postgres updates should be done from within the app."
    fi
else
    echo "Postgres is already installed, just start up."
fi
