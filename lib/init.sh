#!/bin/bash

. "$library_path/yaml_parser.sh"
. "$library_path/wrapper.sh"

eval $(parse_yaml "$config_path/messages.yml" "messages_")

# Initiate
# $1: optional action [reset, purge]
init () {
    docker_compose_path=$current_path/docker-compose.yml

    if [ ! -z $1 ]; then
        optional $@
    fi

    if [ -f "$current_path/docker/parameters" ] || [ -f "$docker_compose_path" ]; then
        files=""

        if [ -f "$current_path/docker/parameters" ]; then
            files+=" $current_path/docker/parameters"
        fi

        if [ -f "$docker_compose_path" ]; then
            files+=" $docker_compose_path"
        fi

        message=`printf "$messages_init_error_exists" "$files"`
        report "error" "$message";
        exit 1;
    fi

    if [ ! -f "$dist_path/parameters.dist" ] && [ ! -f "$dist_path/dist/docker-compose.yml.dist" ]; then
        report "error" "$messages_error_required_files";
        exit 1;
    fi

    accepted = [ '--help', 'initiate', 'purge', 'reset', 'resolver', 'clear', 'compose', 'generate-console', 'generate-composer', 'get_config' ]

    if [[ ${accepted[*]} =~ $1 ]]; then
        process ${@:2}
    else
        process ${@:1}
    fi
}

# Process function
function process()
{
    interaction=true

    if ! options=$(getopt -o n: -l no-interaction: -- "$@")
    then
        report "error" "$message_error_unexpected"
        exit 1
    fi

    accepted=("--no-interaction" "-n")

    while [ $# -gt 0 ]
    do
        case $1 in
        -n|--no-interaction )
            interaction=false
            ;;
        --)
            shift;
            break
            ;;
        -*)
            message=`printf "$messages_console_error_options" "$0" "$1"`
            report "error" "$message";
            exit 1
            ;;
        *)
            break
            ;;
        esac
        shift
    done

    if [ ! -f "$current_path/docker/parameters" ]; then
        parse_config "$dist_path/parameters.dist" "$current_path/docker/parameters" $interaction
    fi

    compose_file
    resolver

    report "info" "$messages_tasks_done";
    exit 0;

}

# Config resolver
function resolver()
{
    config_resolver "$current_path/docker/parameters"
}

# Generate docker-compose file
function compose_file()
{
    docker_compose_path=$current_path/docker-compose.yml

    if [ ! -f "$docker_compose_path" ]; then
        replace_config "$current_path/docker/parameters" "$dist_path/docker-compose.yml.dist" "$docker_compose_path"

        report "info" "$messages_tasks_docker_compose";
    fi
}

# Clean up
# Stop and remove docker container
function purge()
{
    count=`docker ps -q | wc -l`

    if [ $count -ne 0 ]; then
        docker stop $(docker ps -q)
    fi

    count=`docker ps -q -a | wc -l`

    if [ $count -ne 0 ]; then
        docker stop $(docker ps -q)
    fi
}

# Reset
# Call with the reset option
# Remove dist generated files
function reset()
{
    if [ -f $current_path/docker-compose.yml ]; then
        rm -Rf $current_path/docker-compose.yml
    fi

    if [ -f $current_path/docker/parameters ]; then
        rm -Rf $current_path/docker/parameters
    fi
}

# Clear
# Call with the clear option
# Remove generate console and composer files
function clear()
{
    reset

    if [ -f $current_path/docker/console ]; then
        rm -Rf $current_path/docker/console
    fi

    if [ -f $current_path/docker/composer ]; then
        rm -Rf $current_path/docker/composer
    fi
}

# Instantiate
# Call to create default file for docker
function initiate()
{
    if [ ! -d "$current_path/docker" ]; then
        mkdir "$current_path/docker"
    fi

    if [ ! -d "$current_path/docker/dist" ]; then
        mkdir "$current_path/docker/dist"
    fi

    if [ ! -f "$current_path/docker/dist/docker-compose.yml.dist" ]; then
        cat <<EOF >> $current_path/docker/dist/docker-compose.yml.dist
application:
    image: c2is/application
    environment:
        - SYMFONY_ENV=dev
    volumes:
        - {{root_dir}}:/var/www/symfony
    tty: true

php:
    image: c2is/php-fpm:symfony-composer
    environment:
        - SYMFONY_ENV=dev
        - GIT_USERNAME={{git.username}}
        - GIT_EMAIL={{git.email}}
    volumes_from:
        - application
    links:
        - mysql:mysql
    volumes:
        - {{ssh.folder}}:/var/www/.ssh

apache:
    image: c2is/apache:default
    ports:
        - {{port.apache}}:80
    environment:
        - SYMFONY_ENV=dev
    links:
        - php:php
    volumes_from:
        - application
    volumes:
        - ./docker/logs/apache/:/var/log/apache2

mysql:
    image: mysql:5.6
    restart: always
    environment:
        - MYSQL_ROOT_PASSWORD={{database.password}}
        - MYSQL_PASSWORD={{database.password}}
        - MYSQL_USER={{database.username}}
        - MYSQL_DATABASE={{database.name}}
EOF
        report "info" "$messages_initiate_docker_compose"
        report "screen" "$messages_initiate_docker_compose_help"
    fi

    if [ ! -f "$current_path/docker/dist/parameters.dist" ]; then
        password=$(LC_CTYPE=C tr -dc A-Za-z0-9 < /dev/urandom | head -c 32 | xargs)

        cat <<EOF >> $current_path/docker/dist/parameters.dist
# ports
port.apache=81

# database
database.password=$password
database.name=symfony
database.username=root

# git
git.username=is_required
git.email=is_required

# ssh
ssh.folder=is_required

# docker
# On mac
docker.ip=192.168.99.100
# On linux
# Run the 'ifconfig' command and check if the ip match
#docker.ip=172.17.0.1
EOF
        report "info" "$messages_initiate_parameters"
        report "screen" "$messages_initiate_parameters_help"
    fi
}

# Optional
# Execute optional actions
# $1: optional action
function optional()
{
    case "$1" in
    '--help' )
        help
        exit 0;
        ;;
    'initiate' )
        initiate
        exit 0
        ;;
    'purge' )
        purge
        ;;
    'reset' )
        reset
        ;;
    'resolver' )
        resolver
        exit 0
        ;;
    'clear' )
        clear
        exit 0
        ;;
    'compose' )
        if [ -f $current_path/docker-compose.yml ]; then
            rm -Rf $current_path/docker-compose.yml
        fi

        compose_file
        exit 0
        ;;
    'generate-console' )
        console ${@:2}
        exit 0
        ;;
    'generate-composer' )
        composer ${@:2}
        exit 0
        ;;
    'get_config' )
        get_config ${@:2}
        exit 0
        ;;
    esac
}