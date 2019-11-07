#!/bin/bash
set -euo pipefail

echo "**************************************************************"
echo "*                      Installing JIRA                       *"
echo "**************************************************************"

if [ ! -f /etc/jira_installed ]; then
    if [ ! -f ${JIRA_HOME}/dbconfig.xml ]; then
        touch /etc/jira_installed

        mkdir -p ${JIRA_HOME}

        cp /opt/java/openjdk/jre/lib/amd64/jli/libjli.so /usr/lib/

        # Setup jira Daemon
        echo "Setting up JIRA daemon"
        mkdir -p /etc/service/jira
cat << EOF > /etc/service/jira/run
#!/bin/bash
# Setup Catalina Opts
: \${CATALINA_CONNECTOR_PROXYNAME:=}
: \${CATALINA_CONNECTOR_PROXYPORT:=}
: \${CATALINA_CONNECTOR_SCHEME:=http}
: \${CATALINA_CONNECTOR_SECURE:=false}
: \${CATALINA_CONTEXT_PATH:=}

: \${CATALINA_OPTS:=}

: \${JAVA_OPTS:=}

CATALINA_OPTS="\${CATALINA_OPTS} -DcatalinaConnectorProxyName=\${CATALINA_CONNECTOR_PROXYNAME}"
CATALINA_OPTS="\${CATALINA_OPTS} -DcatalinaConnectorProxyPort=\${CATALINA_CONNECTOR_PROXYPORT}"
CATALINA_OPTS="\${CATALINA_OPTS} -DcatalinaConnectorScheme=\${CATALINA_CONNECTOR_SCHEME}"
CATALINA_OPTS="\${CATALINA_OPTS} -DcatalinaConnectorSecure=\${CATALINA_CONNECTOR_SECURE}"
CATALINA_OPTS="\${CATALINA_OPTS} -DcatalinaContextPath=\${CATALINA_CONTEXT_PATH}"

export JAVA_OPTS="\${JAVA_OPTS} \${CATALINA_OPTS}"

# Setup Data Center configuration
if [ ! -s "/etc/container_id" ]; then
  uuidgen > /etc/container_id
fi
CONTAINER_ID=\$(cat /etc/container_id)
CONTAINER_SHORT_ID=\${CONTAINER_ID::8}

: \${CLUSTERED:=false}
: \${JIRA_NODE_ID:=jira_node_\${CONTAINER_SHORT_ID}}
: \${JIRA_SHARED_HOME:=\${JIRA_HOME}/shared}
: \${EHCACHE_PEER_DISCOVERY:=}
: \${EHCACHE_LISTENER_HOSTNAME:=}
: \${EHCACHE_LISTENER_PORT:=}
: \${EHCACHE_LISTENER_SOCKETTIMEOUTMILLIS:=}
: \${EHCACHE_MULTICAST_ADDRESS:=}
: \${EHCACHE_MULTICAST_PORT:=}
: \${EHCACHE_MULTICAST_TIMETOLIVE:=}
: \${EHCACHE_MULTICAST_HOSTNAME:=}

# Cleanly set/unset values in cluster.properties
function set_cluster_property {
    if [ -z \$2 ]; then
        if [ -f "\${JIRA_HOME}/cluster.properties" ]; then
            sed -i -e "/^\${1}/d" "\${JIRA_HOME}/cluster.properties"
        fi
        return
    fi
    if [ ! -f "\${JIRA_HOME}/cluster.properties" ]; then
        echo "\${1}=\${2}" >> "\${JIRA_HOME}/cluster.properties"
    elif grep "^\${1}" "\${JIRA_HOME}/cluster.properties"; then
        sed -i -e "s#^\${1}=.*#\${1}=\${2}#g" "\${JIRA_HOME}/cluster.properties"
    else
        echo "\${1}=\${2}" >> "\${JIRA_HOME}/cluster.properties"
    fi
}

if [ "\${CLUSTERED}" == "true" ]; then
    set_cluster_property "jira.node.id" "\${JIRA_NODE_ID}"
    set_cluster_property "jira.shared.home" "\${JIRA_SHARED_HOME}"
    set_cluster_property "ehcache.peer.discovery" "\${EHCACHE_PEER_DISCOVERY}"
    set_cluster_property "ehcache.listener.hostName" "\${EHCACHE_LISTENER_HOSTNAME}"
    set_cluster_property "ehcache.listener.port" "\${EHCACHE_LISTENER_PORT}"
    set_cluster_property "ehcache.listener.socketTimeoutMillis" "\${EHCACHE_LISTENER_PORT}"
    set_cluster_property "ehcache.multicast.address" "\${EHCACHE_MULTICAST_ADDRESS}"
    set_cluster_property "ehcache.multicast.port" "\${EHCACHE_MULTICAST_PORT}"
    set_cluster_property "ehcache.multicast.timeToLive" "\${EHCACHE_MULTICAST_TIMETOLIVE}"
    set_cluster_property "ehcache.multicast.hostName" "\${EHCACHE_MULTICAST_HOSTNAME}"
fi

# Start Jira as the correct user
if [ "\${UID}" -eq 0 ]; then
    echo "User is currently root. Will change directory ownership to \${RUN_USER}:\${RUN_GROUP}, then downgrade permission to \${RUN_USER}"
    PERMISSIONS_SIGNATURE=\$(stat -c "%u:%U:%a" "\${JIRA_HOME}")
    EXPECTED_PERMISSIONS=\$(id -u \${RUN_USER}):\${RUN_USER}:700
    if [ "\${PERMISSIONS_SIGNATURE}" != "\${EXPECTED_PERMISSIONS}" ]; then
        chmod -R 700 "\${JIRA_HOME}" &&
            chown -R "\${RUN_USER}:\${RUN_GROUP}" "\${JIRA_HOME}"
    fi
    # Now drop privileges
    exec su -s /bin/bash "\${RUN_USER}" -c "\$JIRA_INSTALL_DIR/bin/start-jira.sh -fg \$@"
else
    exec "\$JIRA_INSTALL_DIR/bin/start-jira.sh" "-fg" "\$@"
fi
EOF
        chmod +x /etc/service/jira/run

        echo "Configuring database settings"
cat << EOF > ${JIRA_HOME}/dbconfig.xml
<?xml version="1.0" encoding="UTF-8"?>
<jira-database-config>
    <name>defaultDS</name>
    <delegator-name>default</delegator-name>
    <database-type>postgres72</database-type>
    <schema-name>public</schema-name>
    <jdbc-datasource>
        <url>jdbc:postgresql://localhost:5432/jira</url>
        <driver-class>org.postgresql.Driver</driver-class>
        <validation-query>select version();</validation-query>
        <pool-test-on-borrow>false</pool-test-on-borrow>
        <username>atlassian</username>
        <password>atlassian</password>
        <pool-size>100</pool-size>
        <pool-min-size>20</pool-min-size>
        <pool-remove-abandoned>true</pool-remove-abandoned>
        <pool-remove-abandoned-timeout>300</pool-remove-abandoned-timeout>
        <pool-test-while-idle>true</pool-test-while-idle>
        <pool-test-on-borrow>false</pool-test-on-borrow>
        <min-evictable-idle-time-millis>60000</min-evictable-idle-time-millis>
        <time-between-eviction-runs-millis>300000</time-between-eviction-runs-millis>
        <validation-query-timeout>3</validation-query-timeout>
    </jdbc-datasource>
</jira-database-config>
EOF
        chown -R appbox:appbox ${JIRA_HOME}
        until [[ $(curl -i -H "Accept: application/json" -H "Content-Type:application/json" -X POST "https://api.cylo.io/v1/apps/installed/${INSTANCE_ID}" | grep '200') ]]
           do
           sleep 5
        done
    else
        touch /etc/jira_installed
        cp /opt/java/openjdk/jre/lib/amd64/jli/libjli.so /usr/lib/

        # Setup jira Daemon
        echo "Setting up JIRA daemon"
        mkdir -p /etc/service/jira
cat << EOF > /etc/service/jira/run
#!/bin/bash
# Setup Catalina Opts
: \${CATALINA_CONNECTOR_PROXYNAME:=}
: \${CATALINA_CONNECTOR_PROXYPORT:=}
: \${CATALINA_CONNECTOR_SCHEME:=http}
: \${CATALINA_CONNECTOR_SECURE:=false}
: \${CATALINA_CONTEXT_PATH:=}

: \${CATALINA_OPTS:=}

: \${JAVA_OPTS:=}

CATALINA_OPTS="\${CATALINA_OPTS} -DcatalinaConnectorProxyName=\${CATALINA_CONNECTOR_PROXYNAME}"
CATALINA_OPTS="\${CATALINA_OPTS} -DcatalinaConnectorProxyPort=\${CATALINA_CONNECTOR_PROXYPORT}"
CATALINA_OPTS="\${CATALINA_OPTS} -DcatalinaConnectorScheme=\${CATALINA_CONNECTOR_SCHEME}"
CATALINA_OPTS="\${CATALINA_OPTS} -DcatalinaConnectorSecure=\${CATALINA_CONNECTOR_SECURE}"
CATALINA_OPTS="\${CATALINA_OPTS} -DcatalinaContextPath=\${CATALINA_CONTEXT_PATH}"

export JAVA_OPTS="\${JAVA_OPTS} \${CATALINA_OPTS}"

# Setup Data Center configuration
if [ ! -s "/etc/container_id" ]; then
  uuidgen > /etc/container_id
fi
CONTAINER_ID=\$(cat /etc/container_id)
CONTAINER_SHORT_ID=\${CONTAINER_ID::8}

: \${CLUSTERED:=false}
: \${JIRA_NODE_ID:=jira_node_\${CONTAINER_SHORT_ID}}
: \${JIRA_SHARED_HOME:=\${JIRA_HOME}/shared}
: \${EHCACHE_PEER_DISCOVERY:=}
: \${EHCACHE_LISTENER_HOSTNAME:=}
: \${EHCACHE_LISTENER_PORT:=}
: \${EHCACHE_LISTENER_SOCKETTIMEOUTMILLIS:=}
: \${EHCACHE_MULTICAST_ADDRESS:=}
: \${EHCACHE_MULTICAST_PORT:=}
: \${EHCACHE_MULTICAST_TIMETOLIVE:=}
: \${EHCACHE_MULTICAST_HOSTNAME:=}

# Cleanly set/unset values in cluster.properties
function set_cluster_property {
    if [ -z \$2 ]; then
        if [ -f "\${JIRA_HOME}/cluster.properties" ]; then
            sed -i -e "/^\${1}/d" "\${JIRA_HOME}/cluster.properties"
        fi
        return
    fi
    if [ ! -f "\${JIRA_HOME}/cluster.properties" ]; then
        echo "\${1}=\${2}" >> "\${JIRA_HOME}/cluster.properties"
    elif grep "^\${1}" "\${JIRA_HOME}/cluster.properties"; then
        sed -i -e "s#^\${1}=.*#\${1}=\${2}#g" "\${JIRA_HOME}/cluster.properties"
    else
        echo "\${1}=\${2}" >> "\${JIRA_HOME}/cluster.properties"
    fi
}

if [ "\${CLUSTERED}" == "true" ]; then
    set_cluster_property "jira.node.id" "\${JIRA_NODE_ID}"
    set_cluster_property "jira.shared.home" "\${JIRA_SHARED_HOME}"
    set_cluster_property "ehcache.peer.discovery" "\${EHCACHE_PEER_DISCOVERY}"
    set_cluster_property "ehcache.listener.hostName" "\${EHCACHE_LISTENER_HOSTNAME}"
    set_cluster_property "ehcache.listener.port" "\${EHCACHE_LISTENER_PORT}"
    set_cluster_property "ehcache.listener.socketTimeoutMillis" "\${EHCACHE_LISTENER_PORT}"
    set_cluster_property "ehcache.multicast.address" "\${EHCACHE_MULTICAST_ADDRESS}"
    set_cluster_property "ehcache.multicast.port" "\${EHCACHE_MULTICAST_PORT}"
    set_cluster_property "ehcache.multicast.timeToLive" "\${EHCACHE_MULTICAST_TIMETOLIVE}"
    set_cluster_property "ehcache.multicast.hostName" "\${EHCACHE_MULTICAST_HOSTNAME}"
fi

# Start Jira as the correct user
if [ "\${UID}" -eq 0 ]; then
    echo "User is currently root. Will change directory ownership to \${RUN_USER}:\${RUN_GROUP}, then downgrade permission to \${RUN_USER}"
    PERMISSIONS_SIGNATURE=\$(stat -c "%u:%U:%a" "\${JIRA_HOME}")
    EXPECTED_PERMISSIONS=\$(id -u \${RUN_USER}):\${RUN_USER}:700
    if [ "\${PERMISSIONS_SIGNATURE}" != "\${EXPECTED_PERMISSIONS}" ]; then
        chmod -R 700 "\${JIRA_HOME}" &&
            chown -R "\${RUN_USER}:\${RUN_GROUP}" "\${JIRA_HOME}"
    fi
    # Now drop privileges
    exec su -s /bin/bash "\${RUN_USER}" -c "\$JIRA_INSTALL_DIR/bin/start-jira.sh -fg \$@"
else
    exec "\$JIRA_INSTALL_DIR/bin/start-jira.sh" "-fg" "\$@"
fi
EOF
        chmod +x /etc/service/jira/run

        echo "This is an update, jira updates should be done from within the app.".
        until [[ $(curl -i -H "Accept: application/json" -H "Content-Type:application/json" -X POST "https://api.cylo.io/v1/apps/installed/${INSTANCE_ID}" | grep '200') ]]
           do
           sleep 5
        done
    fi
else
    echo "Jira is already installed, just start up."
fi
