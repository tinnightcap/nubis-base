# This is a bash library for a set functions and variables
# that is used regularly
#
# To use this library just include this line in your bash script:
#
# [ -e /usr/local/lib/nubis/nubis-lib.sh ] && . /usr/local/lib/nubis/nubis-lib.sh || exit 1

if [ "$(nubis-metadata status)" != 'ready' ]; then
    # Assume this is a build and exit
    echo "nubis-metadata reporting $(nubis-metadata status)"
    echo "try again later"
    exit 0
else
    NUBIS_STACK="$(nubis-metadata NUBIS_STACK)"
    NUBIS_ARENA="$(nubis-metadata NUBIS_ARENA)"
    NUBIS_ENVIRONMENT="$(nubis-metadata NUBIS_ENVIRONMENT)"
    NUBIS_PROJECT="$(nubis-metadata NUBIS_PROJECT)"
    NUBIS_PURPOSE="$(nubis-metadata NUBIS_PURPOSE)"
fi

# Set up the consul url
CONSUL="http://localhost:8500/v1/kv/${NUBIS_STACK}/${NUBIS_ARENA}/config"

# Convinience variables
CURL="curl --retry 60 -fks"

# Some bash functions

# Yellow colored echo
# usage: echo_yellow "message"
function echo_yellow {
    echo -e "\033[0;33m$1\033[0m"
}

# Red colored echo
# usage: echo_red "message"
function echo_red {
    echo -e "\033[0;31m$1\033[0m"
}

# Green colored echo
# usage: echo_green "Message"
function echo_green {
    echo -e "\033[0;32m$1\033[0m"
}

# Get Mac address of an interface, this is an internal only function
# Usage: __get_mac eth0
function __get_mac {
    if [[ -z "${1}" ]]; then echo "Usage: $FUNCNAME [interface]"; return 1; fi

    local attempts=10
    local interface=$1
    false
    while [[ "${?}" -gt 0 ]]; do
        [[ "${attempts}" -eq 0 ]] && return
        mac_addr=$(cat /sys/class/net/${interface}/address)
        if [ "${?}" -gt 0 ]; then
            let attempts--
            sleep 3
            false
        fi
    done
    echo "${mac_addr}"
}

# Get eni id of whatever interface we request from
# Usage: get_eni_id eth0
function get_eni_id() {
    if [ -z "$1" ]; then echo "Usage: $FUNCNAME [interface]"; return 1; fi

    local interface=$1
    local mac_addr=$(__get_mac "${interface}")

    eni_id=$(curl --retry 5 --retry-delay 0 -s -fq "http://169.254.169.254/latest/meta-data/network/interfaces/macs/${mac_addr}/interface-id")
    echo "${eni_id}"
}

# Get region aws instance is in
# usage: get_region
function get_region() {
    local region=$(curl --retry 3 --retry-delay 0 -s -fq http://169.254.169.254/latest/dynamic/instance-identity/document | jq '.region' -r)
    echo "${region}"
}

# Get availability_zone aws instance is in
# usage: get_availability_zone
function get_availability_zone() {
    local availability_zone=$(curl --retry 3 --retry-delay 0 -s -fq http://169.254.169.254/latest/meta-data/placement/availability-zone)
    echo "${availability_zone}"
}

# Get instance id of instance
# usage: get_instance_id
function get_instance_id() {
    local instance_id=$(curl --retry 3 --retry-delay 0 -s -fq http://169.254.169.254/latest/meta-data/instance-id)
    echo "${instance_id}"
}

# Gets instance IP, doesn't take into account eni that is attached
# usage: get_instance_ip
function get_instance_ip() {
    local instance_ip=$(curl --retry 3 --retry-delay 0 -s -fq http://169.254.169.254/latest/meta-data/local-ipv4)
    echo "${instance_ip}"
}

# Send message to log
# usage: log migrate "This is a log message"
function log {

    if [ -z "$1" ]; then echo "Usage: $FUNCNAME [log message]"; return 1; fi
    local msg=$1

    LOGGER_BIN='/usr/bin/logger'

    # Set up the logger command if the binary is installed
    if [ ! -x $LOGGER_BIN ]; then
        echo "ERROR: 'logger' binary not found - Aborting"
        echo "ERROR: '$BASH_SOURCE' Line: '$LINENO'"
        exit 2
    else
        echo "${msg}"
        $LOGGER_BIN -i --priority local7.info --tag "$(basename $0)" "${msg}"
    fi
}

# Kills / stop running if this function is ran
# Usage: die
#        die "Message here"
function die() {
    [ -n "$1" ] && log "[ERROR]: $1"
    exit 1
}

# Replace %%VARIABLE_NAME%% with appropriate variable
# runs in consul directory
function consul-search-and-replace() {
    if [ "$NUBIS_ARENA" != "" ]; then
        find /etc/consul -type f -name '*.json' -print0 | xargs -0 --verbose sed -i -e "s/%%ARENA%%/$NUBIS_ARENA/g"
    fi

    if [ "$NUBIS_ENVIRONMENT" != "" ]; then
        find /etc/consul -type f -name '*.json' -print0 | xargs -0 --verbose sed -i -e "s/%%ENVIRONMENT%%/$NUBIS_ENVIRONMENT/g"
    fi

    if [ "$NUBIS_STACK" != "" ]; then
        find /etc/consul -type f -name '*.json' -print0 | xargs -0 --verbose sed -i -e "s/%%STACK%%/$NUBIS_STACK/g"
    fi

    if [ "$NUBIS_PROJECT" != "" ]; then
        find /etc/consul -type f -name '*.json' -print0 | xargs -0 --verbose sed -i -e "s/%%PROJECT%%/$NUBIS_PROJECT/g"
    fi

    if [ "$NUBIS_PURPOSE" != "" ]; then
        find /etc/consul -type f -name '*.json' -print0 | xargs -0 --verbose sed -i -e "s/%%PURPOSE%%/$NUBIS_PURPOSE/g"
    fi
}

# Checks to see if consul is up and running
# usage: consul_up
function consul_up {

    # We run early, so we need to account for Consul's startup time, unfortunately, magic isn't
    # always free
    CONSUL_UP=-1
    COUNT=0
    while [ "$CONSUL_UP" != "0" ]; do
        if [ ${COUNT} == "6" ]; then
            log "ERROR: Timeout while attempting to connect to consul."
            exit 1
        fi
        QUERY=`curl -s ${CONSUL}?raw=1`
        CONSUL_UP=$?

        if [ "$QUERY" != "" ]; then
            CONSUL_UP=-2
        fi

        if [ "$CONSUL_UP" != "0" ]; then
            log "Consul not ready yet ($CONSUL_UP). Sleeping 10 seconds before retrying..."
            sleep 10
            COUNT=${COUNT}+1
        fi
    done
}

# Checks to see if if the consul key is up on consul
# usage: consul_key_up "keyname"
function consul_key_up {

    if [ -z "$1" ]; then echo "Usage: $FUNCNAME [consul key]"; exit 1; fi
    local consul_key=$1

    # Grab the variables from consul
    #+ If this is a new stack we need to wait for the values to be placed in consul
    #+ We will test the first and sleep with a timeout
    KEYS_UP=-1
    COUNT=0
    while [ "$KEYS_UP" != "0" ]; do
        # Try for 20 minutes (30 seconds * 20160 attempts = 604800 seconds / 60 seconds / 60 minutes / 12 hours = 7 days)
        if [ ${COUNT} == "20160" ]; then
            log "ERROR: Timeout while waiting for keys to be populated in consul."
            exit 1
        fi
        QUERY=$(curl -s ${CONSUL}/${consul_key}?raw=1)

        if [ "$QUERY" == "" ]; then
            log "Keys not ready yet. Sleeping 30 seconds before retrying..."
            sleep 30
            COUNT=${COUNT}+1
        else
            log "Key ${consul_key} is ready"
            KEYS_UP=0
        fi
    done
}
