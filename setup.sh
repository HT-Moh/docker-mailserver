#! /bin/bash

# version   v0.3.0 stable
# executed  manually / via Make
# task      wrapper for various setup scripts

SCRIPT='setup.sh'

WHITE="\e[37m"
RED="\e[31m"
PURPLE="\e[35m"
YELLOW="\e[93m"
ORANGE="\e[38;5;214m"
CYAN="\e[96m"
BLUE="\e[34m"
LBLUE="\e[94m"
BOLD="\e[1m"
RESET="\e[0m"

set -euEo pipefail
trap '__log_err "${FUNCNAME[0]:-?}" "${BASH_COMMAND:-?}" "${LINENO:-?}" "${?:-?}"' ERR
trap '_unset_vars || :' EXIT

function __log_err
{
  printf "\n––– ${BOLD}${RED}UNCHECKED ERROR${RESET}\n%s\n%s\n%s\n%s\n\n" \
    "  – script    = ${SCRIPT:-${0}}" \
    "  – function  = ${1} / ${2}" \
    "  – line      = ${3}" \
    "  – exit code = ${4}" >&2

  printf "Make sure you use a version of this script that matches
the version / tag of docker-mailserver. Please read the
'Get the tools' section in the README on GitHub careful-
ly and use ./setup.sh help and read the VERSION section.\n" >&2
}

function _get_current_directory
{
  if dirname "$(readlink -f "${0}")" &>/dev/null
  then
    CDIR="$(dirname "$(readlink -f "${0}")")"
  elif realpath -e -L "${0}" &>/dev/null
  then
    CDIR="$(realpath -e -L "${0}")"
    CDIR="${CDIR%/setup.sh}"
  fi
}

CDIR="$(pwd)"
_get_current_directory

CRI=
INFO=
IMAGE_NAME=
CONTAINER_NAME=
DEFAULT_CONFIG_PATH="${CDIR}/config"
WISHED_CONFIG_PATH=
CONFIG_PATH=
VOLUME=
USE_TTY=

function _check_root
{
  if [[ ${EUID} -ne 0 ]]
  then
    echo "Curently docker-mailserver doesn't support podman's rootless mode, please run this script as root user."
    exit 1
  fi
}

function _update_config_path
{
  if [[ -n ${CONTAINER_NAME} ]]
  then
    VOLUME=$(${CRI} inspect "${CONTAINER_NAME}" \
      --format="{{range .Mounts}}{{ println .Source .Destination}}{{end}}" | \
      grep "/tmp/docker-mailserver$" 2>/dev/null)
  fi

  if [[ -n ${VOLUME} ]]
  then
    CONFIG_PATH=$(echo "${VOLUME}" | awk '{print $1}')
  fi
}

function _docker_image_exists
{
  ${CRI} history -q "${1}" &>/dev/null
  return ${?}
}

function _docker_container
{
  if [[ -n ${CONTAINER_NAME} ]]
  then
    ${CRI} exec "${USE_TTY}" "${CONTAINER_NAME}" "${@}"
  else
    echo "The mailserver is not running!"
    exit 1
  fi
}

function _main
{
  if command -v docker &>/dev/null
  then
    CRI=docker
  elif command -v podman &>/dev/null
  then
    CRI=podman
    _check_root
  else
    echo "No supported Container Runtime Interface detected."
    exit 10
  fi

  INFO=$(${CRI} ps --no-trunc --format "{{.Image}};{{.Names}}" --filter \
    label=org.opencontainers.image.title="docker-mailserver" | tail -1)

  IMAGE_NAME=${INFO%;*}
  CONTAINER_NAME=${INFO#*;}

  if [[ -z ${IMAGE_NAME} ]]
  then
    IMAGE_NAME=${NAME:-docker.io/mailserver/docker-mailserver:latest}
  fi

  if test -t 0
  then
    USE_TTY="-ti"
  else
    # GitHub Actions will fail (or really anything else
    #   lacking an interactive tty) if we don't set a
    #   value here; "-t" alone works for these cases.
    USE_TTY="-t"
  fi

  local OPTIND
  while getopts ":c:i:p:h" OPT
  do
    case ${OPT} in
      i ) IMAGE_NAME="${OPTARG}" ;;
      c )
        # container specified, connect to running instance
        CONTAINER_NAME="${OPTARG}"
        ;;

      p )
        case "${OPTARG}" in
          /* ) WISHED_CONFIG_PATH="${OPTARG}"         ;;
          *  ) WISHED_CONFIG_PATH="${CDIR}/${OPTARG}" ;;
        esac

        if [[ ! -d ${WISHED_CONFIG_PATH} ]]
        then
          echo "Directory doesn't exist"
          _usage
          exit 40
        fi
        ;;

      * )
        echo "Invalid option: -${OPT}" >&2
        ;;

    esac
  done

  shift $(( OPTIND - 1 ))

  if [[ -z ${WISHED_CONFIG_PATH} ]]
  then
    # no wished config path
    _update_config_path

    if [[ -z ${CONFIG_PATH} ]]
    then
      CONFIG_PATH=${DEFAULT_CONFIG_PATH}
    fi
  else
    CONFIG_PATH=${WISHED_CONFIG_PATH}
  fi

  case ${1:-} in
    debug )
      case ${2:-} in
        login          )
          shift 2
          if [[ -z ${1:-} ]]
          then
            _docker_container /bin/bash
          else
            _docker_container /bin/bash -c "${@}"
          fi
          ;;
        * ) _usage ; exit 1 ;;
      esac
      ;;

    help ) _usage ;;
    *    ) _docker_container setup "${@}" ;
  esac
}_usage ; exit 1 ;;

_main "${@}"
