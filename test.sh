#!/bin/bash

# REQUIREMENTS
#
# MACOS:
# - gtruncate:
#   # brew install coreutils


NEO4J_HOSTNAME='http://dist.neo4j.org'
DEFAULT_VERSION='all'
DEFAULT_EDITION='all'
DEFAULT_AUTO_DELAY=3
LAST_VERSION='3.5.16'
SED_CMD="sed -i "
TEST_RETRY=15

# define color variable to be used in echo, cat, ...
if [[ -n "${TERM:-}" && ${TERM} != "dumb" ]] ; then
	readonly BLACK="$(tput setaf 0)"			# Black
	readonly RED="$(tput setaf 1)"			    # Red
	readonly GREEN="$(tput setaf 2)"			# Green
	readonly YELLOW="$(tput setaf 3)"			# Yellow
	readonly BLUE="$(tput setaf 4)"			    # Blue
	readonly PURPLE="$(tput setaf 5)"			# Purple
	readonly CYAN="$(tput setaf 6)"			    # Cyan
	readonly WHITE="$(tput setaf 7)"			# White
	readonly UNDERLINE="$(tput smul)"			# Underline
	readonly ITALIC="$(tput sitm)"              # Italic
	readonly BOLD="$(tput bold)"			    # Bold
	readonly NF="$(tput sgr0)$(tput rmul)"      # No Format
else
	# NO TERM NO COLOR
	readonly BLACK=""		# Black
	readonly RED=""		    # Red
	readonly GREEN=""		# Green
	readonly YELLOW=""	    # Yellow
	readonly BLUE=""		# Blue
	readonly PURPLE=""	    # Purple
	readonly CYAN=""		# Cyan
	readonly WHITE=""		# White
	readonly UNDERLINE=""	# Underline
	readonly ITALIC=""      # Italic
	readonly BOLD=""	    # Bold
	readonly NF=""          # No Format
fi

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

function get_running_message {
  local version=$1
  local instance=$2
  local pid=$3
  local major_version_number=${version%%.*}

  if [ $major_version_number -lt 3 ]; then
    printf \
"
  status '$instance'
  Neo4j Server is running at pid $pid
"
  else
    printf \
"
  status '$instance'
  Neo4j is running at pid $pid
"
  fi
}

function get_not_running_message {
  local version=$1
  local instance=$2
  local major_version_number=${version%%.*}

  if [ $major_version_number -lt 3 ]; then
    printf \
"
  status '$instance'
  Neo4j Server is not running
"
  else
    printf \
"
  status '$instance'
  Neo4j is not running
"
  fi
}

# compare two version strings
# return values are:
# -1 operator <
# 0  operator =
# 1  operator >
function compare_version () {
  if [[ "$1" == "$2" ]]; then
    printf 0
    return
  else
    local IFS=.
    local i ver1=($1) ver2=($2)
    # fill empty fields in ver1 with zeros
    for ((i=${#ver1[@]}; i<${#ver2[@]}; i++)); do
      ver1[i]=0
    done
    for ((i=0; i<${#ver1[@]}; i++)); do
      if [[ -z ${ver2[i]} ]]; then
        # fill empty fields in ver2 with zeros
        ver2[i]=0
      fi
      if ((10#${ver1[i]} > 10#${ver2[i]})); then
        printf 1
        return
      fi
      if ((10#${ver1[i]} < 10#${ver2[i]})); then
        printf -- -1
        return
      fi
    done
  fi
  printf 0
}

###
# Extract version of instance
#
# @param string     instance
###
function instance_version () {
  local instance=$1
  local version

  if [[ -f "${INEO_HOME}/instances/${instance}/.ineo" ]]; then
    version=$(grep neo4j_version "${INEO_HOME}/instances/${instance}/.ineo")
    printf ${version//[^=]*=/}
  fi
}

###
# Return database folder depending on instance
#
# The database folder is the one containing the graph.db folder
#
# @param string     instance
###
function database_folder_instance () {
  local instance=$1
  local version=$(instance_version "${instance}")

  printf $(database_folder_version "${version}")
}

###
# Return database folder depending on version
#
# The database folder is the one containing the graph.db folder
#
# @param string     version
###
function database_folder_version () {
  local version=$1
  local major_version_number=${version%%.*}

  if [ $major_version_number -lt 3 ]; then
    printf "/data"
  else
    printf "/data/databases"
  fi
}

# ==============================================================================
# PROVISION
# ==============================================================================

# make OS specific changed
if [[ "$( uname )" == "Darwin" ]]; then
  # sed command is just incompatible with -i option
	SED_CMD="sed -i ''"
fi

versions=()
editions=()
stoponerror=""
verbose=""
tests=()
while getopts ":v:e:xV" optname
do
  case "${optname}" in
    v)
      versions+=( ${OPTARG} )
      ;;
    e)
      editions+=( ${OPTARG} )
      ;;
    x)
      stoponerror="-x"
      ;;
    V)
      verbose+="-v"
      ;;
    *)
      >&2 echo "Invalid parameters"
      echo "
USAGE:
  test.sh [options] [test name]

DESCRIPTION:
  Start unit tests

OPTIONS:
  -v <version>         Test a specific Neo4j version only or use \"all\"

                       Default: ${DEFAULT_VERSION}

  -e <edition>         Test a specific Neo4j edition (community/enterprise) or use \"all\"

                       Default: ${DEFAULT_EDITION}

  -x                   Stop running tests after the first failure

  -V                   Generate output for every individual test case
"
      exit 1
      ;;
  esac
done

test_name=${@:$OPTIND:1}

# If there are not any argument specified then test just with default Neo4j
# version
if [ ${#versions[@]} -eq 0 ]; then
  versions=("$DEFAULT_VERSION")
fi

# If is all then test with all Neo4j versions
if [ ${versions[0]} == 'all' ]; then
  # check current java version and select "all" version appropriately
  java_version=$(java -version 2>&1 | head -n 1 | cut -d'"' -f2)
  if [[ $(compare_version "${java_version%*.*}" "1.8") == -1 ]]; then
    versions=(1.9.9 2.3.6 3.0.3 3.3.9 ${LAST_VERSION})
  else
    # neo4j 1.9.x is not compatible with java >= 1.8
    versions=(2.3.6 3.0.3 3.3.9 ${LAST_VERSION})
  fi
fi

# If there are not any argument specified then test just with default Neo4j
# edition
if [ ${#editions[@]} -eq 0 ]; then
  editions=("$DEFAULT_EDITION")
fi

# If is all then test with all Neo4j editions
if [ ${editions[0]} == 'all' ]; then
  editions=(community enterprise)
fi

# On fake_neo4j_host is used to save cache tars
mkdir -p fake_neo4j_host

# If some Neo4J version has not been downloaded then try to download it, so can
# test locally reducing remote http requests.
for version in "${versions[@]}"; do
  for edition in "${editions[@]}"; do
    tar_name="neo4j-$edition-$version-unix.tar.gz"
    if [ ! -f fake_neo4j_host/${tar_name} ]; then
      printf "\n\nDownloading ${edition} ${version}\n\n"
      if ! curl -f -o /tmp/${$}.${tar_name} ${NEO4J_HOSTNAME}/${tar_name}; then
        printf "\n\nError downloading ${edition} ${version}\nThe test has been aborted!!!\n"
        exit 0
      fi

      mv /tmp/${$}.${tar_name} fake_neo4j_host/${tar_name}
    fi
  done
done

# fake_ineo_host is used to make a fake update on tests, this will be the last
# ineo script but with a different version
mkdir -p fake_ineo_host

cp ./ineo ./fake_ineo_host/ineo
sed -i.bak "/^\(VERSION=\).*/s//\1x.x.x/" ./fake_ineo_host/ineo

set -e

# Load assert.sh library (More info: http://github.com/lehmannro/assert.sh)
. assert.sh ${stoponerror} ${verbose}

# Set the variables to create instances
# ------------------------------------------------------------------------------

export NEO4J_HOSTNAME="file://$(pwd)/fake_neo4j_host"
export INEO_HOSTNAME="file://$(pwd)/fake_ineo_host"
export INEO_HOME="$(pwd)/ineo_for_test"

# Check for orphaned neo4j process still running from a previous test execution
if [[ $(ps -ef -u $(whoami) | grep "[j]ava" | grep "${INEO_HOME}" | wc -l) -ne 0 ]]; then
    echo -E "${YELLOW}WARNING${NF}: Some old NEO4J process are still running, this might effect test run"
    sleep 1
fi

# ==============================================================================
# PID FUNCTIONS
# ==============================================================================

function set_instance_pid {
  local instance_name=$1
  if [ -f ${INEO_HOME}/instances/${instance_name}/data/neo4j-service.pid ]; then
    assert_raises \
      "test -f ${INEO_HOME}/instances/${instance_name}/data/neo4j-service.pid" 0
    pid=$(head -n 1 ${INEO_HOME}/instances/${instance_name}/data/neo4j-service.pid)
  else
    assert_raises \
      "test -f ${INEO_HOME}/instances/${instance_name}/run/neo4j.pid" 0
    pid=$(head -n 1 ${INEO_HOME}/instances/${instance_name}/run/neo4j.pid)
  fi
}

function assert_run_pid {
  local pid=$1
  local instance_name=$2
  # we need to wait some seconds, because on fast computers the pid will exists
  # even though neo4j terminates due to a configuration error
  assert_try_raises "${TEST_RETRY}" "test $(ps -p $pid -o pid=)" 0

  # NEO4J >= 3.x are not generating DB on create
  if [[ -d "${INEO_HOME}/instances/${instance_name}/data/databases/" ]]; then
    # Check if DB is up and ready, this might need a couple of seconds otherwise NEO4J is not ready
    assert_try_raises "${TEST_RETRY}" "test -f ${INEO_HOME}/instances/${instance_name}/data/databases/graph.db/neostore" 0
    sleep 2
  fi
}

function assert_not_run_pid {
  local pid=$1
  # we need to wait some seconds, because on fast computers the pid will exists
  # even though neo4j terminates due to a configuration error
  assert_try_raises "${TEST_RETRY}" "test $(ps -p $pid -o pid=)" 1
}

# ==============================================================================
# RESET FUNCTION
# ==============================================================================

function setup {
  if [[ "${verbose}" != "" ]]; then
    echo -e "\nStarting test $1"
  fi

  # if execution is too fast, lib folder is still locked
  sleep 1
  rm -fr ineo_for_test

  assert_raises "test -d ineo_for_test" 1
}

# ==============================================================================
# TEST INSTALL
# ==============================================================================

InstallWithIncorrectParameters() {
  setup "${FUNCNAME[0]}"

  local params=(
    "-e $(pwd)/ineo_for_test" 'e'
    "-e$(pwd)/ineo_for_test" 'e'
    "x -d $(pwd)/ineo_for_test" 'x'
    "x -d$(pwd)/ineo_for_test" 'x'
    "-d $(pwd)/ineo_for_test y" 'y'
    "-d$(pwd)/ineo_for_test y" 'y'
  )

  local i
  for ((i=0; i<${#params[*]}; i+=2)); do
    assert_raises "./ineo install ${params[i]}" 1
    assert        "./ineo install ${params[i]}" \
"
  ${PURPLE}Error -> Invalid argument or option ${BOLD}${params[i+1]}

  ${NF}View help about the command ${UNDERLINE}install${NF} typing:
    ${CYAN}ineo help install${NF}
"
  done

  assert_end InstallWithIncorrectParameters
}
tests+=('InstallWithIncorrectParameters')


InstallWithARelativePath() {
  setup "${FUNCNAME[0]}"

  local params=(
    '-d ineo_for_test'
    '-dineo_for_test'
  )

  for param in "${params[@]}"; do
    assert_raises "./ineo install $param" 1
    assert        "./ineo install $param" \
"
  ${PURPLE}Error -> The directory ${BOLD}ineo_for_test${PURPLE} is not an absolute path

  ${NF}Use directories like:
    ${CYAN}/opt/ineo
    ~/.ineo${NF}
"
  done

  assert_end InstallWithARelativePath
}
tests+=('InstallWithARelativePath')


InstallOnAnExistingDirectory() {
  setup "${FUNCNAME[0]}"

  assert_raises "mkdir $(pwd)/ineo_for_test" 0

  local params=(
    "-d $(pwd)/ineo_for_test"
    "-d$(pwd)/ineo_for_test"
  )

  local param
  for param in "${params[@]}"; do
    assert_raises "./ineo install $param" 1
    assert        "./ineo install $param" \
"
  ${PURPLE}Error -> The directory ${BOLD}$(pwd)/ineo_for_test${PURPLE} already exists

  ${NF}If you want reinstall ineo then uninstall it with:
    ${CYAN}ineo uninstall -d \"$(pwd)/ineo_for_test\"

  ${NF}or ensure the directory doesn't contain anything important then remove it with:
    ${CYAN}rm -r \"$(pwd)/ineo_for_test\"${NF}
"
  done

  assert_end InstallOnAnExistingDirectory
}
tests+=('InstallOnAnExistingDirectory')


InstallCorrectly() {
  local params=(
    "-d $(pwd)/ineo_for_test"
    "-d$(pwd)/ineo_for_test"
  )

  for param in "${params[@]}"; do
    setup "${FUNCNAME[0]}"

    assert "./ineo install $param" \
"
  ${GREEN}Ineo was successfully installed in ${BOLD}$(pwd)/ineo_for_test

  ${NF}To start using the ${UNDERLINE}ineo${NF} command reopen your terminal or enter:
    ${CYAN}source ~/.bashrc${NF}
"

    assert_raises "test -d ineo_for_test" 0
    assert_raises "test -d ineo_for_test/bin" 0
    assert_raises "test -d ineo_for_test/instances" 0
    assert_raises "test -d ineo_for_test/cache" 0

    assert_raises \
      "grep -Fq 'export INEO_HOME=$(pwd)/ineo_for_test; export PATH=\$INEO_HOME/bin:\$PATH' ~/.bashrc" 0
  done

  assert_end InstallCorrectly
}
tests+=('InstallCorrectly')

# ==============================================================================
# TEST UNINSTALL
# ==============================================================================

UninstallWithIncorrectParameters() {
  setup "${FUNCNAME[0]}"

  local params=(
    "-e $(pwd)/ineo_for_test" 'e'
    "-e$(pwd)/ineo_for_test" 'e'
    "x -d $(pwd)/ineo_for_test" 'x'
    "x -d$(pwd)/ineo_for_test" 'x'
    "-d $(pwd)/ineo_for_test y" 'y'
    "-d$(pwd)/ineo_for_test y" 'y'
    "-e $(pwd)/ineo_for_test -f" 'e'
    "-e$(pwd)/ineo_for_test -f" 'e'
    "x -d $(pwd)/ineo_for_test -f" 'x'
    "x -d$(pwd)/ineo_for_test -f" 'x'
    "-f -d $(pwd)/ineo_for_test y" 'y'
    "-f -d$(pwd)/ineo_for_test y" 'y'
  )

  local i
  for ((i=0; i<${#params[*]}; i+=2)); do
    assert_raises "./ineo uninstall ${params[i]}" 1
    assert        "./ineo uninstall ${params[i]}" \
"
  ${PURPLE}Error -> Invalid argument or option ${BOLD}${params[i+1]}

  ${NF}View help about the command ${UNDERLINE}uninstall${NF} typing:
    ${CYAN}ineo help uninstall${NF}
"
  done

  assert_end UninstallWithIncorrectParameters
}
tests+=('UninstallWithIncorrectParameters')


UninstallWithARelativeDirectory() {
  setup "${FUNCNAME[0]}"

  local params=(
    '-d ineo_for_test'
    '-dineo_for_test'
  )

  local param
  for param in "${params[@]}"; do
    assert_raises "./ineo uninstall $param" 1
    assert        "./ineo uninstall $param" \
"
  ${PURPLE}Error -> The directory ${BOLD}ineo_for_test${PURPLE} is not an absolute path

  ${NF}Use directories like:
    ${CYAN}/opt/ineo
    ~/.ineo${NF}
"
  done

  assert_end UninstallWithARelativeDirectory
}
tests+=('UninstallWithARelativeDirectory')


UninstallWithANonExistentDirectory() {
  setup "${FUNCNAME[0]}"

  local params=(
    "-d $(pwd)/ineo_for_test"
    "-d$(pwd)/ineo_for_test"
  )

  # Ensure that directory doesn't exists
  assert_raises "test -d $(pwd)/ineo_for_test" 1

  local param
  for param in "${params[@]}"; do
    assert_raises "./ineo uninstall $param" 1
    assert        "./ineo uninstall $param" \
"
  ${PURPLE}Error -> The directory ${BOLD}$(pwd)/ineo_for_test${PURPLE} doesn't exists

  ${NF}Are you sure that Ineo is installed?
"
  done

  assert_end UninstallWithANonExistentDirectory
}
tests+=('UninstallWithANonExistentDirectory')


UninstallWithADirectoryThatDoesntLookLikeAnIneoDirectory() {
  setup "${FUNCNAME[0]}"

  local params=(
    "-d $(pwd)/ineo_for_test"
    "-d$(pwd)/ineo_for_test"
  )

  local param
  for param in "${params[@]}"; do

    # Make an installation
    assert_raises "./ineo install -d $(pwd)/ineo_for_test" 0

    # Remove a directory from Ineo
    assert_raises "rm -fr $(pwd)/ineo_for_test/neo4j" 0

    # Try uninstall saying no to first prompt
    assert "echo -ne 'n\n' | ./ineo uninstall $param" \
"
  ${YELLOW}Warning -> The directory ${RED}$(pwd)/ineo_for_test${YELLOW} doesn't look like an Ineo directory.${NF}
"
    # Ensure that directory exists yet
    assert_raises "test -d $(pwd)/ineo_for_test" 0


    # Try uninstall saying yes to first prompt and no to second prompt
    assert "echo -ne 'y\nn\n' | ./ineo uninstall $param" \
"
  ${YELLOW}Warning -> The directory ${RED}$(pwd)/ineo_for_test${YELLOW} doesn't look like an Ineo directory.${NF}


  ${YELLOW}Warning -> This action will remove everything in ${RED}$(pwd)/ineo_for_test${NF}
"
    # Ensure that directory exists yet
    assert_raises "test -d $(pwd)/ineo_for_test" 0


    # Uninstall saying yes to first prompt and yes to second prompt
    assert "echo -ne 'y\ny\n' | ./ineo uninstall $param" \
"
  ${YELLOW}Warning -> The directory ${RED}$(pwd)/ineo_for_test${YELLOW} doesn't look like an Ineo directory.${NF}


  ${YELLOW}Warning -> This action will remove everything in ${RED}$(pwd)/ineo_for_test${NF}


  ${GREEN}Ineo was successfully uninstalled.${NF}
"
    # Ensure that directory doesn't exists
    assert_raises "test -d $(pwd)/ineo_for_test" 1
  done

  assert_end UninstallWithADirectoryThatDoesntLookLikeAnIneoDirectory
}
tests+=('UninstallWithADirectoryThatDoesntLookLikeAnIneoDirectory')


UninstallWithADirectoryThatDoesntLookLikeAnIneoDirectoryUsingF() {
  setup "${FUNCNAME[0]}"

  local params=(
    "-d $(pwd)/ineo_for_test -f"
    "-d$(pwd)/ineo_for_test -f"
    "-f -d $(pwd)/ineo_for_test"
    "-f -d$(pwd)/ineo_for_test"
  )

  local param
  for param in "${params[@]}"; do
    # Make an installation
    assert_raises "./ineo install -d $(pwd)/ineo_for_test" 0

    # Remove a directory from Ineo
    assert_raises "rm -fr $(pwd)/ineo_for_test/neo4j" 0

    # Ensure that directory exists yet
    assert_raises "test $(pwd)/ineo_for_test" 0

    # Uninstall using force
    assert "./ineo uninstall $param" \
"
  ${GREEN}Ineo was successfully uninstalled.${NF}
"

    # Ensure that directory doesn't exists
    assert_raises "test -d $(pwd)/ineo_for_test" 1
  done

  assert_end UninstallWithADirectoryThatDoesntLookLikeAnIneoDirectoryUsingF
}
tests+=('UninstallWithADirectoryThatDoesntLookLikeAnIneoDirectoryUsingF')


# ==============================================================================
# TEST CREATE
# ==============================================================================

CreateAnInstanceWithoutTheRequiredParameter() {
  setup "${FUNCNAME[0]}"

  # Make an installation
  assert_raises "./ineo install -d $(pwd)/ineo_for_test" 0

  assert_raises "./ineo create" 1
  assert "./ineo create" \
"
  ${PURPLE}Error -> create requires an instance name

  ${NF}View help about the command ${UNDERLINE}create${NF} typing:
    ${CYAN}ineo help create${NF}
"
  assert_end CreateAnInstanceWithoutTheRequiredParameter
}
tests+=('CreateAnInstanceWithoutTheRequiredParameter')

CreateWithIncorrectParameters() {
  setup "${FUNCNAME[0]}"

  local params=(
    "-x" 'x'
    "-d -x" 'x'
    "-f -x" 'x'
    "-p7474 -x" 'x'
    "-s7878 -x" 'x'
    "-v$DEFAULT_VERSION -x" 'x'
    "-p7474 -s7878 -v$DEFAULT_VERSION -d -f -x" 'x'
    "facebook twitter" 'twitter'
    "-x facebook twitter" 'x'
    "-p7474 facebook twitter" 'twitter'
    "-p7474 -s7878 -v$DEFAULT_VERSION -d -f facebook twitter" 'twitter'
  )

  local i
  for ((i=0; i<${#params[*]}; i+=2)); do
    assert_raises "./ineo create ${params[i]}" 1
    assert        "./ineo create ${params[i]}" \
"
  ${PURPLE}Error -> Invalid argument or option ${BOLD}${params[i+1]}

  ${NF}View help about the command ${UNDERLINE}create${NF} typing:
    ${CYAN}ineo help create${NF}
"
  done

  assert_end CreateWithIncorrectParameters
}
tests+=('CreateWithIncorrectParameters')


CreateWithBoltPortOnIncorrectVersion() {
  local params=(
    "-b8486 -v2.3.6 facebook"
    "-p7474 -b8486 -v2.3.6 facebook"
    "-p7474 -s7475 -b8486 -v2.3.6 facebook"
  )

  local i
  for ((i=0; i<${#params[*]}; i+=1)); do
    setup "${FUNCNAME[0]}"

    # Make an installation
    assert_raises "./ineo install -d $(pwd)/ineo_for_test" 0

    assert_raises "./ineo create ${params[i]}" 1
    assert        "./ineo create ${params[i]}" \
"
  ${PURPLE}Error -> Bolt port only works on Neo4j 3.0 or higher

  ${NF}View help about the command ${UNDERLINE}create${NF} typing:
    ${CYAN}ineo help create${NF}
"
  done

  assert_end CreateWithBoltPortOnIncorrectVersion
}
tests+=('CreateWithBoltPortOnIncorrectVersion')


CreateWithIncorrectEdition() {
  local params=(
    "-e lite facebook"
    "-e free facebook"
    "-e paid facebook"
    "-e 1 facebook"
  )

  local i
  for ((i=0; i<${#params[*]}; i+=1)); do
    setup "${FUNCNAME[0]} ${params[i]}"

    # Make an installation
    assert_raises "./ineo install -d $(pwd)/ineo_for_test" 0

    assert_raises "./ineo create ${params[i]}" 1
    assert        "./ineo create ${params[i]}" \
"
  ${PURPLE}Error -> Edition (-e) must be: 'community' or 'enterprise'

  ${NF}View help about the command ${UNDERLINE}create${NF} typing:
    ${CYAN}ineo help create${NF}
"
  done

  assert_end CreateWithIncorrectEdition
}
tests+=('CreateWithIncorrectEdition')


CreateAnInstanceCorrectlyWithDifferentVariationsOfParameters() {
  # The parameters to check are 'port' 'ssl port' 'bolt port' 'version'
  local params=(
    'twitter'                                       '7474' '7475' '7476' "$LAST_VERSION" 'community'
    '-p8484 twitter'                                '8484' '8485' '8486' "$LAST_VERSION" 'community'
    '-s9495 twitter'                                '7474' '9495' '9496' "$LAST_VERSION" 'community'
    '-b9496 twitter'                                '7474' '7475' '9496' "$LAST_VERSION" 'community'
    '-p9494 -s8484 twitter'                         '9494' '8484' '9495' "$LAST_VERSION" 'community'
    '-s8484 -b9496 twitter'                         '7474' '8484' '9496' "$LAST_VERSION" 'community'
    '-p8484 -s9495 -b9499 twitter'                  '8484' '9495' '9499' "$LAST_VERSION" 'community'
    "-v$LAST_VERSION twitter"                       '7474' '7475' '7476' "$LAST_VERSION" 'community'
    "-v$LAST_VERSION -e enterprise twitter"         '7474' '7475' '7476' "$LAST_VERSION" 'enterprise'
    "-v$LAST_VERSION -e community twitter"          '7474' '7475' '7476' "$LAST_VERSION" 'community'
    "-p8484 -v$LAST_VERSION twitter"                '8484' '8485' '8486' "$LAST_VERSION" 'community'
    "-s9495 -v$LAST_VERSION twitter"                '7474' '9495' '9496' "$LAST_VERSION" 'community'
    "-b9496 -v$LAST_VERSION twitter"                '7474' '7475' '9496' "$LAST_VERSION" 'community'
    "-p9494 -s8484 -v$LAST_VERSION twitter"         '9494' '8484' '9495' "$LAST_VERSION" 'community'
    "-p8484 -b9496 -v$LAST_VERSION twitter"         '8484' '8485' '9496' "$LAST_VERSION" 'community'
    "-s8484 -b9496 -v$LAST_VERSION twitter"         '7474' '8484' '9496' "$LAST_VERSION" 'community'
    "-p8484 -s9494 -b9496 -v$LAST_VERSION twitter"  '8484' '9494' '9496' "$LAST_VERSION" 'community'
    '-v2.3.6 twitter'                               '7474' '7475' '' "2.3.6" 'community'
    '-v2.3.6 -e enterprise twitter'                 '7474' '7475' '' "2.3.6" 'enterprise'
    '-v2.3.6 -e community twitter'                  '7474' '7475' '' "2.3.6" 'community'
    '-p8484 -v2.3.6 twitter'                        '8484' '8485' '' "2.3.6" 'community'
    '-s9495 -v2.3.6 twitter'                        '7474' '9495' '' "2.3.6" 'community'
    '-p9494 -s8484 -v2.3.6 twitter'                 '9494' '8484' '' "2.3.6" 'community'
  )

  local i
  for ((i=0; i<${#params[*]}; i+=6)); do
    setup "${FUNCNAME[0]} ${params[i]} (${params[i+1]}-${params[i+2]}-${params[i+3]}-${params[i+4]}-${params[i+5]})"

    local port=${params[i+1]}
    local ssl_port=${params[i+2]}
    local bolt_port=${params[i+3]}
    local version=${params[i+4]}
    local edition=${params[i+5]}
    local major_version_number=${version%%.*}
    if [ $major_version_number -lt 3 ]; then
      local config="$(pwd)/ineo_for_test/instances/twitter/conf/neo4j-server.properties"
    else
      local config="$(pwd)/ineo_for_test/instances/twitter/conf/neo4j.conf"
    fi

    # Make an installation
    assert_raises "./ineo install -d $(pwd)/ineo_for_test" 0

    # Create the instance
    assert "./ineo create ${params[i]}" \
"
  ${GREEN}The instance ${BOLD}twitter${GREEN} was successfully created.${NF}

"

    # Ensure the correct neo4j version was downloaded
    assert_raises \
      "test -f $(pwd)/ineo_for_test/neo4j/neo4j-$edition-$version-unix.tar.gz" 0

    # Ensure neo4j exists
    assert_raises "test -f $(pwd)/ineo_for_test/instances/twitter/bin/neo4j" 0

    # Ensure the correct ports were set
    if [ $major_version_number -lt 3 ]; then
      assert_raises "grep -Fq org\.neo4j\.server\.webserver\.port=$port $config" 0

      assert_raises \
        "grep -Fq org\.neo4j\.server\.webserver\.https\.port=$ssl_port $config" 0
    else
      assert_raises "grep -Fq dbms\.connector\.http\.listen\_address=:$port $config" 0

      assert_raises \
        "grep -Fq dbms\.connector\.https\.listen\_address=:$ssl_port $config" 0

      assert_raises \
        "grep -Fq dbms\.connector\.bolt\.listen\_address=:$bolt_port $config" 0
    fi
  done

  assert_end CreateAnInstanceCorrectlyWithDifferentVariationsOfParameters
}
tests+=('CreateAnInstanceCorrectlyWithDifferentVariationsOfParameters')


CreateAnInstanceCorrectlyWithEveryVersion() {

  local version
  for version in "${versions[@]}"; do
    for edition in "${editions[@]}"; do
      setup "${FUNCNAME[0]} ${version}-${edition}"

      local major_version_number=${version%%.*}
      local minor_version_number=${version%.*}
      if [ $major_version_number -lt 3 ]; then
        local config="$(pwd)/ineo_for_test/instances/twitter/conf/neo4j-server.properties"
      else
        local config="$(pwd)/ineo_for_test/instances/twitter/conf/neo4j.conf"
      fi

      # Make an installation
      assert_raises "./ineo install -d $(pwd)/ineo_for_test" 0

      # Create the instance
      assert "./ineo create -e $edition -p8484 -s9495 -v $version twitter" \
"
  ${GREEN}The instance ${BOLD}twitter${GREEN} was successfully created.${NF}
"
      # Ensure the correct neo4j version was downloaded
      assert_raises \
        "test -f $(pwd)/ineo_for_test/neo4j/neo4j-$edition-$version-unix.tar.gz" 0

      # Ensure neo4j exists
      assert_raises "test -f $(pwd)/ineo_for_test/instances/twitter/bin/neo4j" 0

      # Ensure the correct ports were set
      if [ $major_version_number -lt 3 ]; then
        assert_raises "grep -Fq \"org.neo4j.server.webserver.port=$port\" $config" 0

        assert_raises \
          "grep -Fq \"org.neo4j.server.webserver.https.port=$ssl_port\" $config" 0
      elif [[ "${minor_version_number}" < "3.1" ]]; then
        assert_raises "grep -Fq \"dbms.connector.http.address=localhost:$port\" $config" 0

        assert_raises \
          "grep -Fq \"dbms.connector.https.address=localhost:$ssl_port\" $config" 0
      else
        assert_raises "grep -Fq \"dbms.connector.http.listen_address=:$port\" $config" 0

        assert_raises \
          "grep -Fq \"dbms.connector.https.listen_address=:$ssl_port\" $config" 0
      fi
    done
  done

  assert_end CreateAnInstanceCorrectlyWithEveryVersion
}
tests+=('CreateAnInstanceCorrectlyWithEveryVersion')


CreateAnInstanceWithABadTarAndTryAgainWithDOption() {
  setup "${FUNCNAME[0]}"

  # Truncate a bad version, so is possible a bad tar
  rm -fr bad_tar_for_test
  mkdir bad_tar_for_test

  cp fake_neo4j_host/neo4j-community-${LAST_VERSION}-unix.tar.gz bad_tar_for_test

  local platform=$(uname -s | tr '[:upper:]' '[:lower:]')

  local command_truncate
  if [ $platform = 'darwin' ]; then
    command_truncate=gtruncate
  elif [ $platform = 'linux' ]; then
    command_truncate=truncate
  fi

  $command_truncate -s20MB bad_tar_for_test/neo4j-community-${LAST_VERSION}-unix.tar.gz

  # Change the NEO4J_HOSTNAME for test to download the bad tar
  export NEO4J_HOSTNAME="file://$(pwd)/bad_tar_for_test"

  # Make an installation
  assert_raises "./ineo install -d $(pwd)/ineo_for_test" 0

  # Create the instance with a bad tar version
  assert "./ineo create -v$LAST_VERSION twitter" \
"
  ${PURPLE}Error -> The tar file ${BOLD}neo4j-community-$LAST_VERSION-unix.tar.gz${PURPLE} can't be extracted

  ${NF}Try run the command ${UNDERLINE}create${NF} with the -d option to download the tar file again

"
  # Ensure the bad tar version of neo4j was downloaded
  assert_raises \
    "test -f $(pwd)/ineo_for_test/neo4j/neo4j-community-$LAST_VERSION-unix.tar.gz" 0

  # Ensure the instance doesn't exists
  assert_raises "test -d $(pwd)/ineo_for_test/instances/twitter" 1

  # The bad tar now must be good
  rm -fr bad_tar_for_test
  mkdir bad_tar_for_test

  cp fake_neo4j_host/neo4j-community-${LAST_VERSION}-unix.tar.gz bad_tar_for_test

  # Create the instance with a good tar version
  assert "./ineo create -d -v$LAST_VERSION twitter" \
"
  ${GREEN}The instance ${BOLD}twitter${GREEN} was successfully created.${NF}

"
  # Ensure the correct neo4j version was downloaded
  assert_raises \
    "test -f $(pwd)/ineo_for_test/neo4j/neo4j-community-$LAST_VERSION-unix.tar.gz" 0

  # Ensure neo4j exists
  assert_raises "test -f $(pwd)/ineo_for_test/instances/twitter/bin/neo4j" 0

  # Restore the correct NEO4J_HOSTNAME for test
  export NEO4J_HOSTNAME="file://$(pwd)/fake_neo4j_host"

  assert_end CreateAnInstanceWithABadTarAndTryAgainWithDOption
}
tests+=('CreateAnInstanceWithABadTarAndTryAgainWithDOption')


CreateAnInstanceOnAExistingDirectoryAndTryAgainWithFOption() {
  setup "${FUNCNAME[0]}"

  # Make an installation
  assert_raises "./ineo install -d $(pwd)/ineo_for_test" 0

  # Create the intance directory by hand
  assert_raises "mkdir $(pwd)/ineo_for_test/instances/twitter"

  # Try create the instance
  assert "./ineo create twitter" \
"
  ${PURPLE}Error -> A directory for the instance ${BOLD}twitter${PURPLE} already exists

  ${NF}Maybe the instance already was created or try run the command ${UNDERLINE}install${NF} with the -f option to force the installation
"

  # Ensure the instance directory is empty yet
  assert_raises "test $(ls -A ineo_for_test/instances/twitter)" 1

  # Create the instance with -f option
  assert "./ineo create -f twitter" \
"
  ${GREEN}The instance ${BOLD}twitter${GREEN} was successfully created.${NF}
"

  # Ensure neo4j exists
  assert_raises "test -f $(pwd)/ineo_for_test/instances/twitter/bin/neo4j" 0

  assert_end CreateAnInstanceOnAExistingDirectoryAndTryAgainWithFOption
}
tests+=('CreateAnInstanceOnAExistingDirectoryAndTryAgainWithFOption')


# ==============================================================================
# TEST INSTANCE ACTIONS (START, STATUS, RESTART, STOP)
# ==============================================================================

actions=('start' 'status' 'restart' 'stop')

ActionsWithIncorrectParameters() {
  setup "${FUNCNAME[0]}"

  local params=(
    "-x" 'x'

  )

  local i j
  for ((i=0; i<${#actions[*]}; i+=1)); do
    for ((j=0; j<${#params[*]}; j+=2)); do
      assert_raises "./ineo ${actions[i]} ${params[j]}" 1
      assert        "./ineo ${actions[i]} ${params[j]}" \
"
  ${PURPLE}Error -> Invalid argument or option ${BOLD}${params[j+1]}

  ${NF}View help about the command ${UNDERLINE}${actions[i]}${NF} typing:
    ${CYAN}ineo help ${actions[i]}${NF}
"
    done
  done

  assert_end ActionsWithIncorrectParameters
}
tests+=('ActionsWithIncorrectParameters')


ActionsOnANonExistentInstance() {
  setup "${FUNCNAME[0]}"

  # Make an installation
  assert_raises "./ineo install -d $(pwd)/ineo_for_test" 0

  local action
  for action in "${actions[@]}"; do
    assert_raises "./ineo $action twitter" 1
    assert        "./ineo $action twitter" \
"
  ${PURPLE}Error -> There is not an instance with the name ${BOLD}twitter

  ${NF}You can create an instance with the command:
    ${CYAN}ineo create twitter${NF}

"
  done

  assert_end ActionsOnANonExistentInstance
}
tests+=('ActionsOnANonExistentInstance')


ActionsOnANotProperlyInstalledInstance() {
  setup "${FUNCNAME[0]}"

  # Make an installation
  assert_raises "./ineo install -d $(pwd)/ineo_for_test" 0

  mkdir ineo_for_test/instances/twitter

  local action
  for action in "${actions[@]}"; do
    assert_raises "./ineo $action twitter" 1
    assert        "./ineo $action twitter" \
"
  ${PURPLE}Error -> The instance ${BOLD}twitter${PURPLE} seems that is not properly installed

  ${NF}You can recreate the instance with the command:
    ${CYAN}ineo create -f twitter${NF}
"
  done

  assert_end ActionsOnANotProperlyInstalledInstance
}
tests+=('ActionsOnANotProperlyInstalledInstance')


ExecuteActionsCorrectly() {
  local version
  for version in "${versions[@]}"; do
    for edition in "${editions[@]}"; do
      setup "${FUNCNAME[0]} ${version}-${edition}"

      # Make an installation
      assert_raises "./ineo install -d $(pwd)/ineo_for_test" 0

      assert_raises "./ineo create -e $edition -v $version twitter" 0

      # start
      assert_raises "./ineo start twitter" 0
      set_instance_pid twitter
      assert_run_pid "${pid}" twitter

      # status running
      assert "./ineo status twitter" \
        "$(get_running_message $version twitter $pid)"

      # restart
      assert_raises "./ineo restart twitter" 0
      set_instance_pid twitter
      assert_run_pid "${pid}" twitter

      # status running
      assert "./ineo status twitter" \
        "$(get_running_message $version twitter $pid)"

      # stop
      assert_raises "./ineo stop twitter" 0
      assert_not_run_pid $pid

      # status not running
      assert "./ineo status twitter" \
        "$(get_not_running_message $version twitter)"
    done
  done
  assert_end ExecuteActionsCorrectly
}
tests+=('ExecuteActionsCorrectly')

ExecuteActionsOnVariousInstancesCorrectly() {
  local version
  #local editions=(community)
  for version in "${versions[@]}"; do
    for edition in "${editions[@]}"; do
      setup "${FUNCNAME[0]} ${version}-${edition}"

      # Make an installation
      assert_raises "./ineo install -d $(pwd)/ineo_for_test" 0

      # Test confirming
      if [[ ${version%%.*} < 3 ]]; then
        assert_raises "./ineo create -p7474 -e $edition -v $version twitter" 0
        assert_raises "./ineo create -p8484 -e $edition -v $version facebook" 0
      else
        assert_raises "./ineo create -p7474 -b7575 -e $edition -v $version twitter" 0
        assert_raises "./ineo create -p8484 -b8585 -e $edition -v $version facebook" 0
      fi


      # start
      assert_raises "echo -ne 'y\n' | ./ineo start" 0

      set_instance_pid twitter
      local pid_twitter=$pid
      assert_run_pid "${pid_twitter}" twitter

      set_instance_pid facebook
      local pid_facebook=$pid
      assert_run_pid "${pid_facebook}" facebook

      # status running
      assert "./ineo status" \
"$(get_running_message $version facebook $pid_facebook)
$(get_running_message $version twitter $pid_twitter)"

      # restart
      assert_raises "echo -ne 'y\n' | ./ineo restart" 0

      set_instance_pid twitter
      pid_twitter=$pid
      assert_run_pid "${pid_twitter}" twitter

      set_instance_pid facebook
      pid_facebook=$pid
      assert_run_pid "${pid_facebook}" facebook

      # status running
      assert "./ineo status" \
"$(get_running_message $version facebook $pid_facebook)
$(get_running_message $version twitter $pid_twitter)"

      # stop
      assert_raises "echo -ne 'y\n' | ./ineo stop" 0
      assert_not_run_pid $pid_twitter
      assert_not_run_pid $pid_facebook

      # status not running
      assert "./ineo status" \
"$(get_not_running_message $version facebook $pid_facebook)
$(get_not_running_message $version twitter $pid_twitter)"

      # Test forcing with -q

      # start
      assert_raises "./ineo start -q" 0

      set_instance_pid twitter
      pid_twitter=$pid
      assert_run_pid "${pid_twitter}" twitter

      set_instance_pid facebook
      pid_facebook=$pid
      assert_run_pid "${pid_facebook}" facebook

      # status running
      assert "./ineo status" \
"$(get_running_message $version facebook $pid_facebook)
$(get_running_message $version twitter $pid_twitter)"

      # restart
      assert_raises "./ineo restart -q" 0

      set_instance_pid twitter
      pid_twitter=$pid
      assert_run_pid "${pid_twitter}" twitter

      set_instance_pid facebook
      pid_facebook=$pid
      assert_run_pid "${pid_facebook}" facebook

      # status running
      assert "./ineo status" \
"$(get_running_message $version facebook $pid_facebook)
$(get_running_message $version twitter $pid_twitter)"

      assert_raises "./ineo stop -q" 0
      assert_not_run_pid $pid_twitter
      assert_not_run_pid $pid_facebook

      # status not running
      assert "./ineo status" \
"$(get_not_running_message $version facebook $pid_facebook)
$(get_not_running_message $version twitter $pid_twitter)"
    done
  done
  assert_end ExecuteActionsOnVariousInstancesCorrectly
}
tests+=('ExecuteActionsOnVariousInstancesCorrectly')


# ==============================================================================
# TEST AUTOSTART
# ==============================================================================

AutostartWithoutAnyInstance() {
  setup "${FUNCNAME[0]}"

  # Make an installation
  assert_raises "./ineo install -d $(pwd)/ineo_for_test" 0

  local action
  for action in "${actions[@]}"; do
    assert_raises "./ineo autostart" 1
    assert        "./ineo autostart" \
"
  ${PURPLE}Error -> No instances created yet

  ${NF}Try create an instance with the command:
    ${CYAN}ineo create [your_instance_name]${NF}"
  done

  assert_end AutostartWithoutAnyInstance
}
tests+=('AutostartWithoutAnyInstance')


AutostartSomeInstances() {
  setup "${FUNCNAME[0]}"

  # Make an installation
  assert_raises "./ineo install -d $(pwd)/ineo_for_test" 0

  assert_raises "./ineo create -p 7474 twitter" 0
  assert_raises "./ineo create -p 8484 facebook" 0
  assert_raises "./ineo create -p 9494 apple" 0

  ${SED_CMD} -E "/^.*ineo_start_auto=.*$/ s/.*/ineo_start_auto=1/g" \
    ${INEO_HOME}/instances/apple/.ineo
  ${SED_CMD} -E "/^.*ineo_start_auto=.*$/ s/.*/ineo_start_auto=1/g" \
    ${INEO_HOME}/instances/twitter/.ineo

  assert_raises "./ineo autostart" 0

  set_instance_pid twitter
  local pid_twitter=$pid
  assert_run_pid "${pid_twitter}" twitter

  # should not have started at all, so no PID file yet
  assert_raises \
    "test -f $INEO_HOME/instances/facebook/run/neo4j.pid" 1

  set_instance_pid apple
  local pid_apple=$pid
  assert_run_pid "${pid_apple}" apple

  assert_raises "./ineo stop -q" 0
  assert_not_run_pid $pid_apple
  assert_not_run_pid $pid_twitter

  assert_end AutostartSomeInstances
}
tests+=('AutostartSomeInstances')


AutostartWithDelay() {
  setup "${FUNCNAME[0]}"

  # Make an installation
  assert_raises "./ineo install -d $(pwd)/ineo_for_test" 0

  assert_raises "./ineo create -p 7474 twitter" 0
  assert_raises "./ineo create -p 8484 facebook" 0

  ${SED_CMD} -E "/^.*ineo_start_auto=.*$/ s/.*/ineo_start_auto=1/g" \
    ${INEO_HOME}/instances/facebook/.ineo
  ${SED_CMD} -E "/^.*ineo_start_auto=.*$/ s/.*/ineo_start_auto=1/g" \
    ${INEO_HOME}/instances/twitter/.ineo

  local time=$(date +"%s")
  assert_raises "./ineo autostart" 0
  time=$(($(date +"%s")-${time}))

  assert_raises "[ ${time} -ge ${DEFAULT_AUTO_DELAY} ]" 0

  set_instance_pid twitter
  local pid_twitter=$pid
  assert_run_pid "${pid_twitter}" twitter

  set_instance_pid facebook
  local pid_facebook=$pid
  assert_run_pid "${pid_facebook}" facebook

  assert_raises "./ineo stop -q" 0


  ${SED_CMD} -E "/^.*ineo_start_delay=.*$/ s/.*/ineo_start_delay=0/g" \
    ${INEO_HOME}/instances/facebook/.ineo
  ${SED_CMD} -E "/^.*ineo_start_delay=.*$/ s/.*/ineo_start_delay=0/g" \
    ${INEO_HOME}/instances/twitter/.ineo

  time=$(date +"%s")
  assert_raises "./ineo autostart" 0
  time=$(($(date +"%s")-${time}))

  assert_raises "[ ${time} -lt ${DEFAULT_AUTO_DELAY} ]" 0

  set_instance_pid twitter
  pid_twitter=$pid
  assert_run_pid "${pid_twitter}" twitter

  set_instance_pid facebook
  pid_facebook=$pid
  assert_run_pid "${pid_facebook}" facebook

  assert_raises "./ineo stop -q" 0
  assert_not_run_pid $pid_facebook
  assert_not_run_pid $pid_twitter

  assert_end AutostartWithDelay
}
tests+=('AutostartWithDelay')


AutostartWithPriority() {
  setup "${FUNCNAME[0]}"

  # Make an installation
  assert_raises "./ineo install -d $(pwd)/ineo_for_test" 0

  # testing starting order is not really easy to do, because the autostart
  # is not running in a separate thread/process and cannot be "watched".
  # so the "trick" is to use the same port and see which neo4j is able
  # to start. the first one will win.
  assert_raises "./ineo create -p 7474 twitter" 0
  assert_raises "./ineo create -p 8484 facebook" 0

  ${SED_CMD} -E "/^.*ineo_start_auto=.*$/ s/.*/ineo_start_auto=1/g" \
    ${INEO_HOME}/instances/facebook/.ineo
  ${SED_CMD} -E "/^.*ineo_start_auto=.*$/ s/.*/ineo_start_auto=1/g" \
    ${INEO_HOME}/instances/twitter/.ineo

  ${SED_CMD} -E "/^.*ineo_start_priority=.*$/ s/.*/ineo_start_priority=10/g" \
    ${INEO_HOME}/instances/facebook/.ineo
  ${SED_CMD} -E "/^.*ineo_start_priority=.*$/ s/.*/ineo_start_priority=100/g" \
    ${INEO_HOME}/instances/twitter/.ineo

  assert_contains "./ineo autostart" ".*start 'twitter'.*start 'facebook'.*"

  set_instance_pid twitter
  pid_twitter=$pid
  assert_run_pid "${pid_twitter}" twitter

  set_instance_pid facebook
  pid_facebook=$pid
  assert_run_pid "${pid_facebook}" facebook

  assert_raises "./ineo stop -q" 0

  ${SED_CMD} -E "/^.*ineo_start_priority=.*$/ s/.*/ineo_start_priority=1/g" \
    ${INEO_HOME}/instances/twitter/.ineo
  ${SED_CMD} -E "/^.*ineo_start_priority=.*$/ s/.*/ineo_start_priority=100/g" \
    ${INEO_HOME}/instances/facebook/.ineo

  assert_contains "./ineo autostart" ".*start 'facebook'.*start 'twitter'.*"
  assert_raises "./ineo stop -q" 0

  assert_end AutostartWithPriority
}
tests+=('AutostartWithPriority')


# ==============================================================================
# TEST INSTANCES
# ==============================================================================

ListWithIncorrectParameters() {
  setup "${FUNCNAME[0]}"

  params=(
    'wrong'
    '-q'
  )

  local param
  for param in "${params[@]}"; do
    assert_raises "./ineo list $param" 1
    assert        "./ineo list $param" \
"
  ${PURPLE}Error -> Invalid argument or option ${BOLD}$param

  ${NF}View help about the command ${UNDERLINE}list${NF} typing:
    ${CYAN}ineo help list${NF}
"
  done

  assert_end ListWithIncorrectParameters
}
tests+=('ListWithIncorrectParameters')


ListCorrectly() {
  for version in "${versions[@]}"; do
    for edition in "${editions[@]}"; do
      setup "${FUNCNAME[0]} ${version}-${edition}"

      # Make an installation
      assert_raises "./ineo install -d $(pwd)/ineo_for_test" 0

      assert_raises "./ineo create -p7474 -s8484 -e $edition -v $version twitter" 0
      assert_raises "./ineo create -p7575 -s8585 -e $edition -v $version facebook" 0

      assert_raises "./ineo list" 0
      if [ ${version%%.*} -lt 3 ]; then
        assert        "./ineo list" \
"
  > instance 'facebook'
    VERSION: $version
    EDITION: $edition
    PATH:    $INEO_HOME/instances/facebook
    PORT:    7575
    HTTPS:   8585

  > instance 'twitter'
    VERSION: $version
    EDITION: $edition
    PATH:    $INEO_HOME/instances/twitter
    PORT:    7474
    HTTPS:   8484
"
      else
        assert        "./ineo list" \
"
  > instance 'facebook'
    VERSION: $version
    EDITION: $edition
    PATH:    $INEO_HOME/instances/facebook
    PORT:    7575
    HTTPS:   8585
    BOLT:    8586

  > instance 'twitter'
    VERSION: $version
    EDITION: $edition
    PATH:    $INEO_HOME/instances/twitter
    PORT:    7474
    HTTPS:   8484
    BOLT:    8485
"
      fi
    done
  done

  assert_end ListCorrectly
}
tests+=('ListCorrectly')


ListAliases() {
  setup "${FUNCNAME[0]}"

  # Make an installation
  assert_raises "./ineo install -d $(pwd)/ineo_for_test" 0

  assert_raises "./ineo create twitter" 0

  if [ ${version%%.*} -lt 3 ]; then
    assert        "./ineo ls" \
"
  > instance 'twitter'
    VERSION: ${versions[@]:(-1)}
    EDITION: ${editions[0]}
    PATH:    $INEO_HOME/instances/twitter
    PORT:    7474
    HTTPS:   7475
"
      else
        assert        "./ineo ls" \
"
  > instance 'twitter'
    VERSION: ${versions[@]:(-1)}
    EDITION: ${editions[0]}
    PATH:    $INEO_HOME/instances/twitter
    PORT:    7474
    HTTPS:   7475
    BOLT:    7476
"
  fi

  if [ ${version%%.*} -lt 3 ]; then
    assert        "./ineo instances" \
"
  > instance 'twitter'
    VERSION: ${versions[@]:(-1)}
    EDITION: ${editions[0]}
    PATH:    $INEO_HOME/instances/twitter
    PORT:    7474
    HTTPS:   7475
"
      else
        assert        "./ineo instances" \
"
  > instance 'twitter'
    VERSION: ${versions[@]:(-1)}
    EDITION: ${editions[0]}
    PATH:    $INEO_HOME/instances/twitter
    PORT:    7474
    HTTPS:   7475
    BOLT:    7476
"
  fi

  assert_end ListAliases
}
tests+=('ListAliases')


# ==============================================================================
# TEST VERSIONS
# ==============================================================================

VersionsWithIncorrectParameters() {
  setup "${FUNCNAME[0]}"

  local params=(
    'wrong' 'wrong'
    '-q' 'q'
  )

  local param
  for ((i=0; i<${#params[*]}; i+=2)); do
    assert_raises "./ineo versions ${params[i]}" 1
    assert        "./ineo versions ${params[i]}" \
"
  ${PURPLE}Error -> Invalid argument or option ${BOLD}${params[i+1]}

  ${NF}View help about the command ${UNDERLINE}versions${NF} typing:
    ${CYAN}ineo help versions${NF}
"
  done

  assert_end VersionsWithIncorrectParameters
}
tests+=('VersionsWithIncorrectParameters')


VersionsCorrectly() {
  setup "${FUNCNAME[0]}"

  # Make an installation
  assert_raises "./ineo install -d $(pwd)/ineo_for_test" 0

  assert_raises "./ineo versions" 0
  assert_raises "./ineo versions -u" 0

  assert_end VersionsCorrectly
}
tests+=('VersionsCorrectly')


# ==============================================================================
# TEST SHELL
# ==============================================================================

ShellWithIncorrectParameters() {
  setup "${FUNCNAME[0]}"

  local params=(
    "-x" 'x'
    "-x -y" 'x'
    "-x twitter" 'x'
    "facebook twitter" 'twitter'
    "-x facebook twitter" 'x'
  )

  local i
  for ((i=0; i<${#params[*]}; i+=2)); do
    assert_raises "./ineo shell ${params[i]}" 1
    assert        "./ineo shell ${params[i]}" \
"
  ${PURPLE}Error -> Invalid argument or option ${BOLD}${params[i+1]}

  ${NF}View help about the command ${UNDERLINE}shell${NF} typing:
    ${CYAN}ineo help shell${NF}
"
  done

  assert_end ShellWithIncorrectParameters
}
tests+=('ShellWithIncorrectParameters')


StartAShellWithoutTheRequiredParameter() {
  setup "${FUNCNAME[0]}"

  # Make an installation
  assert_raises "./ineo install -d $(pwd)/ineo_for_test" 0

  assert_raises "./ineo shell" 1
  assert "./ineo shell" \
"
  ${PURPLE}Error -> shell requires an instance name

  ${NF}View help about the command ${UNDERLINE}shell${NF} typing:
    ${CYAN}ineo help shell${NF}
"

  assert_end StartAShellWithoutTheRequiredParameter
}
tests+=('StartAShellWithoutTheRequiredParameter')


StartAShellWithANonExistentInstance() {
  setup "${FUNCNAME[0]}"

  # Make an installation
  assert_raises "./ineo install -d $(pwd)/ineo_for_test" 0

  assert_raises "./ineo shell twitter" 1
  assert        "./ineo shell twitter" \
"
  ${PURPLE}Error -> There is not an instance with the name ${BOLD}twitter

  ${NF}List installed instances typing:
    ${CYAN}ineo list${NF}
"

  assert_end StartAShellWithANonExistentInstance
}
tests+=('StartAShellWithANonExistentInstance')


# ==============================================================================
# TEST CONSOLE
# ==============================================================================

ConsoleWithIncorrectParameters() {
  setup "${FUNCNAME[0]}"

  local params=(
    "-x" 'x'
    "-x -y" 'x'
    "-x twitter" 'x'
    "facebook twitter" 'twitter'
    "-x facebook twitter" 'x'
  )

  local i
  for ((i=0; i<${#params[*]}; i+=2)); do
    assert_raises "./ineo console ${params[i]}" 1
    assert        "./ineo console ${params[i]}" \
"
  ${PURPLE}Error -> Invalid argument or option ${BOLD}${params[i+1]}

  ${NF}View help about the command ${UNDERLINE}console${NF} typing:
    ${CYAN}ineo help console${NF}
"
  done

  assert_end ConsoleWithIncorrectParameters
}
tests+=('ConsoleWithIncorrectParameters')


StartModeConsoleWithoutTheRequiredParameter() {
  setup "${FUNCNAME[0]}"

  # Make an installation
  assert_raises "./ineo install -d $(pwd)/ineo_for_test" 0

  assert_raises "./ineo console" 1
  assert "./ineo console" \
"
  ${PURPLE}Error -> console requires an instance name

  ${NF}View help about the command ${UNDERLINE}console${NF} typing:
    ${CYAN}ineo help console${NF}
"

  assert_end StartModeConsoleWithoutTheRequiredParameter
}
tests+=('StartModeConsoleWithoutTheRequiredParameter')


StartModeConsoleWithANonExistentInstance() {
  setup "${FUNCNAME[0]}"

  # Make an installation
  assert_raises "./ineo install -d $(pwd)/ineo_for_test" 0

  assert_raises "./ineo console twitter" 1
  assert        "./ineo console twitter" \
"
  ${PURPLE}Error -> There is not an instance with the name ${BOLD}twitter

  ${NF}You can create an instance with the command:
    ${CYAN}ineo create twitter${NF}
"

  assert_end StartModeConsoleWithANonExistentInstance
}
tests+=('StartModeConsoleWithANonExistentInstance')


# ==============================================================================
# TEST DESTROY
# ==============================================================================

DestroyWithIncorrectParameters() {
  setup "${FUNCNAME[0]}"

  local params=(
    "-x" 'x'
    "-x -y" 'x'
    "-x twitter" 'x'
    "facebook twitter" 'twitter'
    "-x facebook twitter" 'x'
  )

  local i
  for ((i=0; i<${#params[*]}; i+=2)); do
    assert_raises "./ineo destroy ${params[i]}" 1
    assert        "./ineo destroy ${params[i]}" \
"
  ${PURPLE}Error -> Invalid argument or option ${BOLD}${params[i+1]}

  ${NF}View help about the command ${UNDERLINE}destroy${NF} typing:
    ${CYAN}ineo help destroy${NF}
"
  done

  assert_end DestroyWithIncorrectParameters
}
tests+=('DestroyWithIncorrectParameters')


DestroyAnInstanceWithoutTheRequiredParameter() {
  setup "${FUNCNAME[0]}"

  # Make an installation
  assert_raises "./ineo install -d $(pwd)/ineo_for_test" 0

  assert_raises "./ineo destroy" 1
  assert "./ineo destroy" \
"
  ${PURPLE}Error -> destroy requires an instance name

  ${NF}View help about the command ${UNDERLINE}destroy${NF} typing:
    ${CYAN}ineo help destroy${NF}
"

  assert_end DestroyAnInstanceWithoutTheRequiredParameter
}
tests+=('DestroyAnInstanceWithoutTheRequiredParameter')


DestroyANonExistentInstance() {
  setup "${FUNCNAME[0]}"

  # Make an installation
  assert_raises "./ineo install -d $(pwd)/ineo_for_test" 0

  assert_raises "./ineo destroy twitter" 1
  assert        "./ineo destroy twitter" \
"
  ${PURPLE}Error -> There is not an instance with the name ${BOLD}twitter

  ${NF}List installed instances typing:
    ${CYAN}ineo list${NF}
"

  assert_end DestroyANonExistentInstance
}
tests+=('DestroyANonExistentInstance')


DestroyCorrectly() {
  local version
  for version in "${versions[@]}"; do
    for edition in "${editions[@]}"; do
      setup "${FUNCNAME[0]} ${version}-${edition}"

      # Make an installation
      assert_raises "./ineo install -d $(pwd)/ineo_for_test" 0

      # Test confirming without an instance running

      assert_raises "./ineo create -e $edition -v $version twitter" 0
      sleep 1
      assert_raises "echo -ne 'y\n' | ./ineo destroy twitter" 0

      assert_raises "./ineo create -e $edition -v $version twitter" 0
      sleep 1
      assert "echo -ne 'y\n' | ./ineo destroy twitter" \
"
  ${YELLOW}Warning -> Destroying the instance ${RED}twitter${YELLOW} will remove all data for this instance${NF}



  ${GREEN}The instance ${BOLD}twitter${GREEN} was successfully destroyed.${NF}
"

      # Test confirming with an instance running

      assert_raises "./ineo create -e $edition -v $version twitter" 0
      assert_raises "./ineo start twitter" 0

      set_instance_pid twitter
      assert_run_pid "${pid}" twitter

      sleep 1
      assert_raises "echo -ne 'y\ny\n' | ./ineo destroy twitter" 0

      assert_not_run_pid $pid

      # Test forcing without an instance running

      assert_raises "./ineo create -e $edition -v $version twitter" 0

      sleep 1
      assert_raises "./ineo destroy -f twitter" 0

      assert_raises "./ineo create -e $edition -v $version twitter" 0
      sleep 1
      assert "./ineo destroy -f twitter" \
"
  ${GREEN}The instance ${BOLD}twitter${GREEN} was successfully destroyed.${NF}
"

      # Test forcing with an instance running

      assert_raises "./ineo create -e $edition -v $version twitter" 0
      assert_raises "./ineo start twitter" 0

      set_instance_pid twitter
      assert_run_pid "${pid}" twitter

      sleep 1
      assert_raises "./ineo destroy -f twitter" 0

      assert_not_run_pid $pid
    done
  done
  assert_end DestroyCorrectly
}
tests+=('DestroyCorrectly')


# ==============================================================================
# TEST SET-PORT
# ==============================================================================

SetPortWithIncorrectParameters() {
  setup "${FUNCNAME[0]}"

  local params=(
    "-x" 'x'
    "-x -y" 'x'
    "-x twitter" 'x'
    "facebook 9898 twitter" 'twitter'
    "-x facebook 9898" 'x'
  )

  local i
  for ((i=0; i<${#params[*]}; i+=2)); do
    assert_raises "./ineo set-port ${params[i]}" 1
    assert        "./ineo set-port ${params[i]}" \
"
  ${PURPLE}Error -> Invalid argument or option ${BOLD}${params[i+1]}

  ${NF}View help about the command ${UNDERLINE}set-port${NF} typing:
    ${CYAN}ineo help set-port${NF}
"
  done

  assert_end SetPortWithIncorrectParameters
}
tests+=('SetPortWithIncorrectParameters')


SetPortWithoutTheRequireParameters() {
  setup "${FUNCNAME[0]}"

  # Make an installation
  assert_raises "./ineo install -d $(pwd)/ineo_for_test" 0

  assert_raises "./ineo create twitter" 0

  assert_raises "./ineo set-port" 1
  assert        "./ineo set-port" \
"
  ${PURPLE}Error -> ${BOLD}set-port${PURPLE} requires an instance name and a port number

  ${NF}View help about the command ${UNDERLINE}set-port${NF} typing:
    ${CYAN}ineo help set-port${NF}
"

  assert_raises "./ineo set-port twitter" 1
  assert        "./ineo set-port twitter" \
"
  ${PURPLE}Error -> ${BOLD}set-port${PURPLE} requires an instance name and a port number

  ${NF}View help about the command ${UNDERLINE}set-port${NF} typing:
    ${CYAN}ineo help set-port${NF}
"

  assert_end SetPortWithoutTheRequireParameters
}
tests+=('SetPortWithoutTheRequireParameters')


SetPortOnANonExistentInstance() {
  setup "${FUNCNAME[0]}"

  # Make an installation
  assert_raises "./ineo install -d $(pwd)/ineo_for_test" 0

  assert_raises "./ineo set-port twitter 7575" 1
  assert        "./ineo set-port twitter 7474" \
"
  ${PURPLE}Error -> There is not an instance with the name ${BOLD}twitter${PURPLE} or is not properly installed

  ${NF}List installed instances typing:
    ${CYAN}ineo list${NF}
"

  assert_end SetPortOnANonExistentInstance
}
tests+=('SetPortOnANonExistentInstance')


SetPortWithAnIncorrectNumberPort() {
  setup "${FUNCNAME[0]}"

  # Make an installation
  assert_raises "./ineo install -d $(pwd)/ineo_for_test" 0

  assert_raises "./ineo create twitter" 0

  assert_raises "./ineo set-port twitter aaa" 1
  assert        "./ineo set-port twitter aaa" \
"
  ${PURPLE}Error -> The port must be a positive integer number

  ${NF}View help about the command ${UNDERLINE}set-port${NF} typing:
    ${CYAN}ineo help set-port${NF}
"

  assert_end SetPortWithAnIncorrectNumberPort
}
tests+=('SetPortWithAnIncorrectNumberPort')


SetPortWithAnIncorrectOutOfRangePort() {
  setup "${FUNCNAME[0]}"

  # Make an installation
  assert_raises "./ineo install -d $(pwd)/ineo_for_test" 0

  assert_raises "./ineo create twitter" 0

  assert_raises "./ineo set-port twitter 65536" 1
  assert        "./ineo set-port twitter 65536" \
"
  ${PURPLE}Error -> The port must be a number between ${BOLD}1${PURPLE} and ${BOLD}65535

  ${NF}View help about the command ${UNDERLINE}set-port${NF} typing:
    ${CYAN}ineo help set-port${NF}
"

  assert_raises "./ineo set-port twitter 0" 1
  assert        "./ineo set-port twitter 0" \
"
  ${PURPLE}Error -> The port must be a number between ${BOLD}1${PURPLE} and ${BOLD}65535

  ${NF}View help about the command ${UNDERLINE}set-port${NF} typing:
    ${CYAN}ineo help set-port${NF}
"

  assert_end SetPortWithAnIncorrectOutOfRangePort
}
tests+=('SetPortWithAnIncorrectOutOfRangePort')


SetBoltPortWithIncorrectVersion() {
  setup "${FUNCNAME[0]}"

  # Make an installation
  assert_raises "./ineo install -d $(pwd)/ineo_for_test" 0

  # Create a instance with version 2.3.6 but Bolt port only works on version
  # 3.0 or higher
  assert_raises "./ineo create -v 2.3.6 twitter" 0

  assert_raises "./ineo set-port -b twitter 7575" 1
  assert        "./ineo set-port -b twitter 7474" \
"
  ${PURPLE}Error -> Bolt port only works with Neo4j 3.0 or higher

  ${NF}View help about the command ${UNDERLINE}set-port${NF} typing:
    ${CYAN}ineo help set-port${NF}
"

  assert_end SetBoltPortWithIncorrectVersion
}
tests+=('SetBoltPortWithIncorrectVersion')


SetBoltAndSslPortAtTheSameTime() {
  setup "${FUNCNAME[0]}"

  # Make an installation
  assert_raises "./ineo install -d $(pwd)/ineo_for_test" 0

  assert_raises "./ineo create -v 3.0.3 twitter" 0

  assert_raises "./ineo set-port -s -b twitter 7575" 1
  assert        "./ineo set-port -s -b twitter 7474" \
"
  ${PURPLE}Error -> ${BOLD}set-port${PURPLE} can't set bolt and ssl port at the same time

  ${NF}View help about the command ${UNDERLINE}set-port${NF} typing:
    ${CYAN}ineo help set-port${NF}

"

  assert_end SetBoltAndSslPortAtTheSameTime
}
tests+=('SetBoltAndSslPortAtTheSameTime')


SetPortCorrectly() {
  local version
  for version in "${versions[@]}"; do
    for edition in "${editions[@]}"; do
      setup "${FUNCNAME[0]} ${version}-${edition}"

      # Make an installation
      assert_raises "./ineo install -d $(pwd)/ineo_for_test" 0

      # Test http port
      assert_raises "./ineo create -e $edition -v $version twitter" 0

      assert_raises "./ineo set-port twitter 1" 0
      assert        "./ineo set-port twitter 1" \
"
  ${GREEN}The http port was successfully changed to ${BOLD}1${GREEN}.${NF}
"

      assert_raises "./ineo set-port twitter 65535" 0
      assert        "./ineo set-port twitter 65535" \
"
  ${GREEN}The http port was successfully changed to ${BOLD}65535${GREEN}.${NF}
"

      # Test https port
      assert_raises "./ineo set-port -s twitter 1" 0
      assert        "./ineo set-port -s twitter 1" \
"
  ${GREEN}The https port was successfully changed to ${BOLD}1${GREEN}.${NF}
"

      assert_raises "./ineo set-port -s twitter 65535" 0
      assert        "./ineo set-port -s twitter 65535" \
"
  ${GREEN}The https port was successfully changed to ${BOLD}65535${GREEN}.${NF}
"

      # Test bolt port
      if [ ${version%%.*} -gt 2 ]; then
        assert_raises "./ineo set-port -b twitter 1" 0
        assert        "./ineo set-port -b twitter 1" \
"
  ${GREEN}The bolt port was successfully changed to ${BOLD}1${GREEN}.${NF}
"

        assert_raises "./ineo set-port -b twitter 65535" 0
        assert        "./ineo set-port -b twitter 65535" \
"
  ${GREEN}The bolt port was successfully changed to ${BOLD}65535${GREEN}.${NF}
"
      fi
    done
  done
  assert_end SetPortCorrectly
}
tests+=('SetPortCorrectly')

# ==============================================================================
# TEST SET-CONFIG
# ==============================================================================

SetConfigWithIncorrectParameters() {
  setup "${FUNCNAME[0]}"

  local params=(
    "-x" 'x'
  )

  local i
  for ((i=0; i<${#params[*]}; i+=2)); do
    assert_raises "./ineo set-config ${params[i]}" 1
    assert        "./ineo set-config ${params[i]}" \
"
  ${PURPLE}Error -> Invalid argument or option ${BOLD}${params[i+1]}

  ${NF}View help about the command ${UNDERLINE}set-config${NF} typing:
    ${CYAN}ineo help set-config${NF}
"
  done

  params=(
    "instance"
    "instance param"
    "instance param value more"
    "-d instance"
    "-d instance param value"
  )

  for ((i=0; i<${#params[*]}; i+=1)); do
    assert_raises "./ineo set-config ${params[i]}" 1
    assert        "./ineo set-config ${params[i]}" \
"
  ${PURPLE}Error -> ${BOLD}set-config${PURPLE} requires an instance name, parameter and value

  ${NF}View help about the command ${UNDERLINE}set-config${NF} typing:
    ${CYAN}ineo help set-config${NF}
"
  done

  assert_end SetConfigWithIncorrectParameters
}
tests+=('SetConfigWithIncorrectParameters')

SetConfigWithCorrectParameters() {
  setup "${FUNCNAME[0]}"

  # Make an installation
  assert_raises "./ineo install -d $(pwd)/ineo_for_test" 0

  assert_raises "./ineo create twitter" 0

  # add non-existing param
  assert_raises "grep twitter.one.a $(pwd)/ineo_for_test/instances/twitter/conf/neo4j.conf" 1
  assert_raises "./ineo set-config twitter twitter.one.a 1" 0
  assert_raises "grep twitter.one.a $(pwd)/ineo_for_test/instances/twitter/conf/neo4j.conf" 0
  assert        "grep twitter.one.a $(pwd)/ineo_for_test/instances/twitter/conf/neo4j.conf" "twitter.one.a=1"

  # uncomment existing param
  assert_raises "grep '^#dbms.active_database' $(pwd)/ineo_for_test/instances/twitter/conf/neo4j.conf" 0
  assert        "grep '^#dbms.active_database' $(pwd)/ineo_for_test/instances/twitter/conf/neo4j.conf" "#dbms.active_database=graph.db"
  assert_raises "./ineo set-config twitter dbms.active_database graph.db" 0
  assert_raises "grep '^dbms.active_database' $(pwd)/ineo_for_test/instances/twitter/conf/neo4j.conf" 0
  assert        "grep '^dbms.active_database' $(pwd)/ineo_for_test/instances/twitter/conf/neo4j.conf" "dbms.active_database=graph.db"

  # uncomment existing param with backslash
  assert_raises "grep '^#dbms.directories.data' $(pwd)/ineo_for_test/instances/twitter/conf/neo4j.conf" 0
  assert        "grep '^#dbms.directories.data' $(pwd)/ineo_for_test/instances/twitter/conf/neo4j.conf" "#dbms.directories.data=data"
  assert_raises "./ineo set-config twitter dbms.directories.data /path/to/data" 0
  assert_raises "grep '^dbms.directories.data' $(pwd)/ineo_for_test/instances/twitter/conf/neo4j.conf" 0
  assert        "grep '^dbms.directories.data' $(pwd)/ineo_for_test/instances/twitter/conf/neo4j.conf" "dbms.directories.data=/path/to/data"

  # comment existing param
  assert_raises "grep '^dbms.connector.bolt.enabled' $(pwd)/ineo_for_test/instances/twitter/conf/neo4j.conf" 0
  assert        "grep '^dbms.connector.bolt.enabled' $(pwd)/ineo_for_test/instances/twitter/conf/neo4j.conf" "dbms.connector.bolt.enabled=true"
  assert_raises "./ineo set-config -d twitter dbms.connector.bolt.enabled" 0
  assert_raises "grep '^#dbms.connector.bolt.enabled' $(pwd)/ineo_for_test/instances/twitter/conf/neo4j.conf" 0
  assert        "grep '^#dbms.connector.bolt.enabled' $(pwd)/ineo_for_test/instances/twitter/conf/neo4j.conf" "#dbms.connector.bolt.enabled=true"

  assert "./ineo set-config -q twitter dbms.connector.bolt.enabled true" ""
  assert "./ineo set-config -dq twitter dbms.connector.bolt.enabled" ""

  assert_end SetConfigWithCorrectParameters
}
tests+=('SetConfigWithCorrectParameters')

# ==============================================================================
# TEST GET-CONFIG
# ==============================================================================

GetConfigWithIncorrectParameters() {
  setup "${FUNCNAME[0]}"

  local params=(
    "-x" 'x'
  )

  local i
  for ((i=0; i<${#params[*]}; i+=2)); do
    assert_raises "./ineo get-config ${params[i]}" 1
    assert        "./ineo get-config ${params[i]}" \
"
  ${PURPLE}Error -> Invalid argument or option ${BOLD}${params[i+1]}

  ${NF}View help about the command ${UNDERLINE}get-config${NF} typing:
    ${CYAN}ineo help get-config${NF}
"
  done

  params=(
    "instance"
    "-a instance param"
  )

  for ((i=0; i<${#params[*]}; i+=1)); do
    assert_raises "./ineo get-config ${params[i]}" 1
    assert        "./ineo get-config ${params[i]}" \
"
  ${PURPLE}Error -> ${BOLD}get-config${PURPLE} requires an instance name and parameter

  ${NF}View help about the command ${UNDERLINE}get-config${NF} typing:
    ${CYAN}ineo help get-config${NF}
"
  done

  assert_end GetConfigWithIncorrectParameters
}
tests+=('GetConfigWithIncorrectParameters')

GetConfigWithCorrectParameters() {
  setup "${FUNCNAME[0]}"

  # Make an installation
  assert_raises "./ineo install -d $(pwd)/ineo_for_test" 0

  assert_raises "./ineo create twitter" 0
  assert_raises "./ineo create facebook" 0
  assert_raises "./ineo create apple" 0

  local params=(
    "twitter"
    "facebook"
    "apple"
  )

  local i
  for ((i=0; i<${#params[*]}; i+=1)); do
    # insert param to all instances
    assert_raises "./ineo set-config ${params[i]} all.one.a 1" 0
    assert_raises "./ineo set-config ${params[i]} all.one.b 2" 0
    assert_raises "./ineo set-config ${params[i]} all.two.a 3" 0
    assert_raises "./ineo set-config ${params[i]} all.two.b 4" 0
  done

  # insert param to all but one instance
  assert_raises "./ineo set-config twitter twitter.one.a 1" 0
  assert_raises "./ineo set-config twitter twitter.one.b 2" 0
  assert_raises "./ineo set-config apple apple.one.a 1" 0
  assert_raises "./ineo set-config apple apple.one.b 2" 0

  # try all formats with single instance and single param
  assert_raises "./ineo get-config twitter twitter.one.a" 0
  assert        "./ineo get-config twitter twitter.one.a" "twitter.one.a=1"

  assert_raises "./ineo get-config -o list twitter twitter.one.a" 0
  assert        "./ineo get-config -o list twitter twitter.one.a" \
"
  > instance 'twitter'
    twitter.one.a=1"

  assert_raises "./ineo get-config -o ini twitter twitter.one.a" 0
  assert        "./ineo get-config -o ini twitter twitter.one.a" "[twitter]\ntwitter.one.a=1"

  assert_raises "./ineo get-config -o line twitter twitter.one.a" 0
  assert        "./ineo get-config -o line twitter twitter.one.a" "twitter.one.a=1"

  assert_raises "./ineo get-config -o value twitter twitter.one.a" 0
  assert        "./ineo get-config -o value twitter twitter.one.a" "1"


  # try all formats with all instance and single param existing in all instances
  assert_raises "./ineo get-config -a all.one.a" 0
  assert        "./ineo get-config -a all.one.a" \
"
  > instance 'apple'
    all.one.a=1


  > instance 'facebook'
    all.one.a=1


  > instance 'twitter'
    all.one.a=1"

  assert_raises "./ineo get-config -a -o list all.one.a" 0
  assert        "./ineo get-config -a -o list all.one.a" \
"
  > instance 'apple'
    all.one.a=1


  > instance 'facebook'
    all.one.a=1


  > instance 'twitter'
    all.one.a=1"


  assert_raises "./ineo get-config -a -o ini all.one.a" 0
  assert        "./ineo get-config -a -o ini all.one.a" \
"[apple]
all.one.a=1

[facebook]
all.one.a=1

[twitter]
all.one.a=1"

  assert_raises "./ineo get-config -a -o line all.one.a" 0
  assert        "./ineo get-config -a -o line all.one.a" \
"
  > instance 'apple'
    all.one.a=1


  > instance 'facebook'
    all.one.a=1


  > instance 'twitter'
    all.one.a=1"


  assert_raises "./ineo get-config -a -o value all.one.a" 0
  assert        "./ineo get-config -a -o value all.one.a" \
"
  > instance 'apple'
    all.one.a=1


  > instance 'facebook'
    all.one.a=1


  > instance 'twitter'
    all.one.a=1"


  # try multi formats with all instance and single param existing in one instance
  assert_raises "./ineo get-config -a -o list twitter.one.a" 0
  assert        "./ineo get-config -a -o list twitter.one.a" \
"
  > instance 'apple'
    WARNING: \"twitter.one.a\" doesn't exist in the \"apple\" configuration


  > instance 'facebook'
    WARNING: \"twitter.one.a\" doesn't exist in the \"facebook\" configuration


  > instance 'twitter'
    twitter.one.a=1"

  assert_raises "./ineo get-config -a -o ini twitter.one.a" 0
  assert        "./ineo get-config -a -o ini twitter.one.a" \
"[apple]
WARNING: \"twitter.one.a\" doesn't exist in the \"apple\" configuration

[facebook]
WARNING: \"twitter.one.a\" doesn't exist in the \"facebook\" configuration

[twitter]
twitter.one.a=1"


  # try quiet mode on multi formats with all instance and single param existing in one instance
  assert_raises "./ineo get-config -a -q -o list twitter.one.a" 0
  assert        "./ineo get-config -a -q -o list twitter.one.a" \
"
  > instance 'apple'


  > instance 'facebook'


  > instance 'twitter'
    twitter.one.a=1"

  assert_raises "./ineo get-config -a -q -o ini twitter.one.a" 0
  assert        "./ineo get-config -a -q -o ini twitter.one.a" \
"[apple]
[facebook]
[twitter]
twitter.one.a=1"


  # try all formats with one instance and asterix param
  assert_raises "./ineo get-config -o list twitter twitter.one.*" 0
  assert        "./ineo get-config -o list twitter twitter.one.*" \
"
  > instance 'twitter'
    twitter.one.a=1
    twitter.one.b=2"

  assert_raises "./ineo get-config -o ini twitter twitter.one.*" 0
  assert        "./ineo get-config -o ini twitter twitter.one.*" \
"[twitter]
twitter.one.a=1
twitter.one.b=2"

  assert_raises "./ineo get-config -o line twitter twitter.one.*" 0
  assert        "./ineo get-config -o line twitter twitter.one.*" \
"twitter.one.a=1
twitter.one.b=2"

  assert_raises "./ineo get-config -o line twitter all.*.b" 0
  assert        "./ineo get-config -o line twitter all.*.b" \
"all.one.b=2
all.two.b=4"

  assert_raises "./ineo get-config -o value twitter twitter.one.*" 0
  assert        "./ineo get-config -o value twitter twitter.one.*" \
"twitter.one.a=1
twitter.one.b=2"

  # try multi formats with all instance and asterix param
  assert_raises "./ineo get-config -a -o list twitter.one.*" 0
  assert        "./ineo get-config -a -o list twitter.one.*" \
"
  > instance 'apple'


  > instance 'facebook'


  > instance 'twitter'
    twitter.one.a=1
    twitter.one.b=2"

  assert_raises "./ineo get-config -a -o ini twitter.one.*" 0
  assert        "./ineo get-config -a -o ini twitter.one.*" \
"[apple]
[facebook]
[twitter]
twitter.one.a=1
twitter.one.b=2"


  assert_end GetConfigWithCorrectParameters
}
tests+=('GetConfigWithCorrectParameters')

# ==============================================================================
# TEST BACKUP
# ==============================================================================

BackupWithIncorrectParameters() {
  setup "${FUNCNAME[0]}"

  local params=(
    "-x" 'x'
    "-x -y" 'x'
    "-x twitter" 'x'
    "facebook twitter" 'twitter'
    "-x facebook" 'x'
  )

  local i
  for ((i=0; i<${#params[*]}; i+=2)); do
    assert_raises "./ineo backup ${params[i]}" 1
    assert        "./ineo backup ${params[i]}" \
"
  ${PURPLE}Error -> Invalid argument or option ${BOLD}${params[i+1]}

  ${NF}View help about the command ${UNDERLINE}backup${NF} typing:
    ${CYAN}ineo help backup${NF}
"
  done

  assert_end BackupWithIncorrectParameters
}
tests+=('BackupWithIncorrectParameters')


BackupWithoutTheRequireParameters() {
  setup "${FUNCNAME[0]}"

  # Make an installation
  assert_raises "./ineo install -d $(pwd)/ineo_for_test" 0

  assert_raises "./ineo create twitter" 0

  assert_raises "./ineo backup" 1
  assert        "./ineo backup" \
"
  ${PURPLE}Error -> ${BOLD}backup${PURPLE} requires an instance name

  ${NF}View help about the command ${UNDERLINE}backup${NF} typing:
    ${CYAN}ineo help backup${NF}
"

  assert_end BackupWithoutTheRequireParameters
}
tests+=('BackupWithoutTheRequireParameters')


BackupOnANonExistentInstance() {
  setup "${FUNCNAME[0]}"

  # Make an installation
  assert_raises "./ineo install -d $(pwd)/ineo_for_test" 0

  assert_raises "./ineo backup twitter" 1
  assert        "./ineo backup twitter" \
"
  ${PURPLE}Error -> There is not an instance with the name ${BOLD}twitter${PURPLE} or is not properly installed

  ${NF}List installed instances typing:
    ${CYAN}ineo instances${NF}
"

  assert_end BackupOnANonExistentInstance
}
tests+=('BackupOnANonExistentInstance')


BackupCorrectly() {
  local version
  local minor_version_number
  for version in "${versions[@]}"; do
    for edition in "${editions[@]}"; do
      setup "${FUNCNAME[0]} ${version}-${edition}"

      # Make an installation
      assert_raises "./ineo install -d $(pwd)/ineo_for_test" 0

      # Test confirming without an instance running

      assert_raises "./ineo create -e $edition -v $version twitter" 0

      minor_version_number=${version%.*}
      if [[ "${minor_version_number}" < "3.1" ]]; then
        # only neo4j >=3.x is supported for backup
        assert_raises "./ineo backup twitter" 1

        assert "./ineo backup twitter" \
"
  ${PURPLE}Error -> ${BOLD}backup${PURPLE} requires instance to run Neo4j version 3.1 or higher

  ${NF}View help about the command ${UNDERLINE}backup${NF} typing:
    ${CYAN}ineo help backup${NF}

"
        continue
      fi


      # start to create graph.db
      assert_raises "./ineo start twitter" 0
      set_instance_pid twitter
      assert_run_pid "${pid}" twitter

      assert_raises "./ineo backup -p /tmp/ineo$$.dump twitter" 0
      assert_raises "test -s /tmp/ineo$$.dump" 0
      rm /tmp/ineo$$.dump

      # check if instance was restarted after backup
      set_instance_pid twitter
      assert_run_pid "${pid}" twitter

      assert_raises "./ineo stop twitter" 0
      assert_not_run_pid $pid

    done
  done
  assert_end BackupCorrectly
}
tests+=('BackupCorrectly')


BackupPath() {
  setup "${FUNCNAME[0]}"

  # Make an installation
  assert_raises "./ineo install -d $(pwd)/ineo_for_test" 0

  assert_raises "./ineo create -v ${LAST_VERSION} twitter" 0

  # start to create graph.db
  assert_raises "./ineo start twitter" 0
  set_instance_pid twitter
  assert_run_pid "${pid}" twitter

  # stop
  assert_raises "./ineo stop twitter" 0
  assert_not_run_pid $pid

  # check path including filename
  assert_raises "./ineo backup -p /tmp/ineo$$.dump twitter" 0
  assert_raises "test -s /tmp/ineo$$.dump" 0
  rm /tmp/ineo$$.dump

  assert "./ineo status twitter" \
    "$(get_not_running_message $version twitter)"

  # check path without filename
  mkdir /tmp/ineo$$
  assert_raises "./ineo backup -p /tmp/ineo$$/ twitter" 0
  assert_raises "test -s /tmp/ineo$$/ineo_twitter_*.dump" 0
  rm -rf /tmp/ineo$$/

  assert_end BackupPath
}
tests+=('BackupPath')



# ==============================================================================
# TEST RESTORE
# ==============================================================================

RestoreWithIncorrectParameters() {
  setup "${FUNCNAME[0]}"

  local params=(
    "-x" 'x'
    "-x -y" 'x'
    "-x twitter" 'x'
    "-x facebook" 'x'
  )

  local i
  for ((i=0; i<${#params[*]}; i+=2)); do
    assert_raises "./ineo restore ${params[i]}" 1
    assert        "./ineo restore ${params[i]}" \
"
  ${PURPLE}Error -> Invalid argument or option ${BOLD}${params[i+1]}

  ${NF}View help about the command ${UNDERLINE}restore${NF} typing:
    ${CYAN}ineo help restore${NF}
"
  done

  assert_end RestoreWithIncorrectParameters
}
tests+=('RestoreWithIncorrectParameters')


RestoreWithoutTheRequireParameters() {
  setup "${FUNCNAME[0]}"

  # Make an installation
  assert_raises "./ineo install -d $(pwd)/ineo_for_test" 0

  assert_raises "./ineo create twitter" 0

  assert_raises "./ineo restore nosuchfile" 1
  assert        "./ineo restore nosuchfile" \
"
  ${PURPLE}Error -> No dump file ${BOLD}nosuchfile${PURPLE} found${NF}
"

  assert_raises "./ineo restore ineo" 1
  assert        "./ineo restore ineo" \
"
  ${PURPLE}Error -> ${BOLD}restore${PURPLE} requires an instance name

  ${NF}View help about the command ${UNDERLINE}restore${NF} typing:
    ${CYAN}ineo help restore${NF}
"

  assert_end RestoreWithoutTheRequireParameters
}
tests+=('RestoreWithoutTheRequireParameters')


RestoreOnANonExistentInstance() {
  setup "${FUNCNAME[0]}"

  # Make an installation
  assert_raises "./ineo install -d $(pwd)/ineo_for_test" 0

  assert_raises "./ineo restore ineo twitter" 1
  assert        "./ineo restore ineo twitter" \
"
  ${PURPLE}Error -> There is not an instance with the name ${BOLD}twitter${PURPLE} or is not properly installed

  ${NF}List installed instances typing:
    ${CYAN}ineo instances${NF}
"

  assert_end RestoreOnANonExistentInstance
}
tests+=('RestoreOnANonExistentInstance')


RestoreCorrectly() {
  local version
  local minor_version_number
  for version in "${versions[@]}"; do
    for edition in "${editions[@]}"; do
      setup "${FUNCNAME[0]} ${version}-${edition}"

      # Make an installation
      assert_raises "./ineo install -d $(pwd)/ineo_for_test" 0

      # Test confirming without an instance running

      assert_raises "./ineo create -e $edition -v $version twitter" 0

      minor_version_number=${version%.*}
      if [[ "${minor_version_number}" < "3.1" ]]; then
        # only neo4j >=3.x is supported for restore
        assert_raises "./ineo restore ineo twitter" 1

        assert "./ineo restore ineo twitter" \
"
  ${PURPLE}Error -> ${BOLD}restore${PURPLE} requires instance to run Neo4j version 3.1 or higher

  ${NF}View help about the command ${UNDERLINE}restore${NF} typing:
    ${CYAN}ineo help restore${NF}

"
        continue
      fi


      # create dump file, if not exists yet
      if [[ ! -e /tmp/ineo$$.dump ]]; then
        # start to create graph.db
        assert_raises "./ineo start twitter" 0
        set_instance_pid twitter
        assert_run_pid "${pid}" twitter

        assert_raises "./ineo backup -p /tmp/ineo$$.dump twitter" 0
        assert_raises "test -s /tmp/ineo$$.dump" 0
      fi

      # Neo4J versions >= 3.x are not creating empty graph.db without a start of the instance
      if [[ ! -d "ineo_for_test/instances/twitter/data/databases/graph.db/" ]]; then
        assert_raises "./ineo start twitter" 0
        set_instance_pid twitter
        assert_run_pid "${pid}" twitter
      fi
      assert_raises "./ineo restore -f /tmp/ineo$$.dump twitter" 0


      # check if instance can be started after restore
      assert_raises "./ineo start twitter" 0
      set_instance_pid twitter
      assert_run_pid "${pid}" twitter

      assert_raises "./ineo stop twitter" 0
      assert_not_run_pid $pid

    done
  done

  rm /tmp/ineo$$.dump

  assert_end RestoreCorrectly
}
tests+=('RestoreCorrectly')


RestoreForce() {
  setup "${FUNCNAME[0]}"

  # Make an installation
  assert_raises "./ineo install -d $(pwd)/ineo_for_test" 0

  assert_raises "./ineo create -v ${LAST_VERSION} twitter" 0

  # start to create graph.db
  assert_raises "./ineo start twitter" 0
  set_instance_pid twitter
  assert_run_pid "${pid}" twitter

  assert_raises "./ineo backup -p /tmp/ineo$$.dump twitter" 0
  assert_raises "test -s /tmp/ineo$$.dump" 0

  # use force to prevent interaction
  assert_raises "./ineo restore -f /tmp/ineo$$.dump twitter" 0

  assert_raises "echo -ne 'y\n' | ./ineo restore /tmp/ineo$$.dump twitter" 0

#  assert "echo -ne 'y\n' | ./ineo restore /tmp/ineo$$.dump twitter" \
#"
#  ${YELLOW}Warning -> ${RED}restore${YELLOW} on the instance ${BOLD}twitter${YELLOW} will overwrite all existing data for this instance${NF}
#
#
#  ${GREEN}The data for the instance ${BOLD}twitter${GREEN} was successfully restored${NF}
#"


  # check if instance can be started after restore
  assert_raises "./ineo start twitter" 0
  set_instance_pid twitter
  assert_run_pid "${pid}" twitter

  assert_raises "./ineo stop twitter" 0
  assert_not_run_pid $pid

  rm /tmp/ineo$$.dump


  assert_end RestoreForce
}
tests+=('RestoreForce')



# ==============================================================================
# TEST CLEAR-DATA
# ==============================================================================

ClearDataWithIncorrectParameters() {
  setup "${FUNCNAME[0]}"

  local params=(
    "-x" 'x'
    "-x -y" 'x'
    "-x twitter" 'x'
    "facebook twitter" 'twitter'
    "-x facebook" 'x'
  )

  local i
  for ((i=0; i<${#params[*]}; i+=2)); do
    assert_raises "./ineo delete-db ${params[i]}" 1
    assert        "./ineo delete-db ${params[i]}" \
"
  ${PURPLE}Error -> Invalid argument or option ${BOLD}${params[i+1]}

  ${NF}View help about the command ${UNDERLINE}delete-db${NF} typing:
    ${CYAN}ineo help delete-db${NF}
"
  done

  assert_end ClearDataWithIncorrectParameters
}
tests+=('ClearDataWithIncorrectParameters')


ClearDataWithoutTheRequireParameters() {
  setup "${FUNCNAME[0]}"

  # Make an installation
  assert_raises "./ineo install -d $(pwd)/ineo_for_test" 0

  assert_raises "./ineo create twitter" 0

  assert_raises "./ineo delete-db" 1
  assert        "./ineo delete-db" \
"
  ${PURPLE}Error -> ${BOLD}delete-db${PURPLE} requires an instance name

  ${NF}View help about the command ${UNDERLINE}delete-db${NF} typing:
    ${CYAN}ineo help delete-db${NF}
"

  assert_end ClearDataWithoutTheRequireParameters
}
tests+=('ClearDataWithoutTheRequireParameters')


ClearDataOnANonExistentInstance() {
  setup "${FUNCNAME[0]}"

  # Make an installation
  assert_raises "./ineo install -d $(pwd)/ineo_for_test" 0

  assert_raises "./ineo delete-db twitter" 1
  assert        "./ineo delete-db twitter" \
"
  ${PURPLE}Error -> There is not an instance with the name ${BOLD}twitter${PURPLE} or is not properly installed

  ${NF}List installed instances typing:
    ${CYAN}ineo list${NF}
"

  assert_end ClearDataOnANonExistentInstance
}
tests+=('ClearDataOnANonExistentInstance')


ClearDataCorrectly() {
  local version
  local dbFolder
  for version in "${versions[@]}"; do
    for edition in "${editions[@]}"; do
      setup "${FUNCNAME[0]} ${version}-${edition}"
      dbFolder=$(database_folder_version "${version}")

      # Make an installation
      assert_raises "./ineo install -d $(pwd)/ineo_for_test" 0

      # Test confirming without an instance running

      assert_raises "./ineo create -e $edition -v $version twitter" 0
      # Create a fake directory
      assert_raises "mkdir ineo_for_test/instances/twitter${dbFolder}/graph.db" 0
      assert_raises "test -d ineo_for_test/instances/twitter${dbFolder}/graph.db" 0

      assert_raises "echo -ne 'y\n' | ./ineo delete-db twitter" 0

      # Create a fake directory
      assert_raises "mkdir ineo_for_test/instances/twitter${dbFolder}/graph.db" 0
      assert_raises "test -d ineo_for_test/instances/twitter${dbFolder}/graph.db" 0

      assert "echo -ne 'y\n' | ./ineo delete-db twitter" \
"
  ${YELLOW}Warning -> ${RED}delete-db${YELLOW} on the instance ${BOLD}twitter${YELLOW} will remove all data for this instance${NF}


  ${GREEN}The data for the instance ${BOLD}twitter${GREEN} was successfully removed${NF}
"

      assert_raises "test -d ineo_for_test/instances/twitter${dbFolder}/graph.db" 1

      # Test confirming with an instance running

      # Create a fake directory
      assert_raises "mkdir ineo_for_test/instances/twitter${dbFolder}/graph.db" 0
      assert_raises "test -d ineo_for_test/instances/twitter${dbFolder}/graph.db" 0

      assert_raises "./ineo start twitter" 0

      set_instance_pid twitter
      assert_run_pid "${pid}" twitter

      assert_raises "echo -ne 'y\ny\n' | ./ineo delete-db twitter" 0

      assert_raises "test -d ineo_for_test/instances/twitter${dbFolder}/graph.db" 1

      assert_not_run_pid $pid

      # Test forcing without an instance running

      # Create a fake directory
      assert_raises "mkdir ineo_for_test/instances/twitter${dbFolder}/graph.db" 0
      assert_raises "test -d ineo_for_test/instances/twitter${dbFolder}/graph.db" 0

      assert_raises "./ineo delete-db -f twitter" 0

      assert_raises "test -d ineo_for_test/instances/twitter${dbFolder}/graph.db" 1

      # Create a fake directory
      assert_raises "mkdir ineo_for_test/instances/twitter${dbFolder}/graph.db" 0
      assert_raises "test -d ineo_for_test/instances/twitter${dbFolder}/graph.db" 0

      assert "./ineo delete-db -f twitter" \
"
  ${GREEN}The data for the instance ${BOLD}twitter${GREEN} was successfully removed${NF}
"

      assert_raises "test -d ineo_for_test/instances/twitter${dbFolder}/graph.db" 1

      # Test forcing with an instance running

      # Create a fake directory
      assert_raises "mkdir ineo_for_test/instances/twitter${dbFolder}/graph.db" 0
      assert_raises "test -d ineo_for_test/instances/twitter${dbFolder}/graph.db" 0

      assert_raises "./ineo start twitter" 0

      set_instance_pid twitter
      assert_run_pid "${pid}" twitter

      assert_raises "./ineo delete-db -f twitter" 0

      assert_not_run_pid $pid

      assert_raises "test -d ineo_for_test/instances/twitter${dbFolder}/graph.db" 1
    done
  done
  assert_end ClearDataCorrectly
}
tests+=('ClearDataCorrectly')


ClearDataCorrectlyWithoutADatabaseFile() {
  local version
  for version in "${versions[@]}"; do
    for edition in "${editions[@]}"; do
      setup "${FUNCNAME[0]} ${version}-${edition}"

      # Make an installation
      assert_raises "./ineo install -d $(pwd)/ineo_for_test" 0

      # Test confirming without an instance running

      assert_raises "./ineo create -e $edition -v $version twitter" 0
      assert_raises "test -d ineo_for_test/instances/twitter/data/databases/graph.db" 1

      assert_raises "echo -ne 'y\n' | ./ineo delete-db twitter" 0

      assert "echo -ne 'y\n' | ./ineo delete-db twitter" \
"
  ${YELLOW}Warning -> ${RED}delete-db${YELLOW} on the instance ${BOLD}twitter${YELLOW} will remove all data for this instance${NF}


  There is not a database on the instance ${UNDERLINE}twitter${NF}, so nothing was removed
"

      # Test confirming with an instance running

      assert_raises "./ineo start twitter" 0

      set_instance_pid twitter
      assert_run_pid "${pid}" twitter

      assert_raises "echo -ne 'y\ny\n' | ./ineo delete-db twitter" 0

      assert_raises "test -d ineo_for_test/instances/twitter/data/databases/graph.db" 1

      assert_not_run_pid $pid

      # Test forcing without an instance running

      assert_raises "./ineo delete-db -f twitter" 0

      assert "./ineo delete-db -f twitter" \
"
  There is not a database on the instance ${UNDERLINE}twitter${NF}, so nothing was removed
"

      # Test forcing with an instance running

      assert_raises "./ineo start twitter" 0

      set_instance_pid twitter
      assert_run_pid "${pid}" twitter

      assert_raises "./ineo delete-db -f twitter" 0

      assert_not_run_pid $pid

      assert_raises "test -d ineo_for_test/instances/twitter/data/databases/graph.db" 1
    done
  done
  assert_end ClearDataCorrectlyWithoutADatabaseFile
}
tests+=('ClearDataCorrectlyWithoutADatabaseFile')

# ==============================================================================
# TEST UPDATE
# ==============================================================================

UpdateWithIncorrectParameters() {
  setup "${FUNCNAME[0]}"

  local params=(
    "-x" '-x'
    "-x -y" '-x'
    "facebook" 'facebook'
    "facebook twitter" 'facebook'
    "-x facebook" '-x'
  )

  local i
  for ((i=0; i<${#params[*]}; i+=2)); do
    assert_raises "./ineo update ${params[i]}" 1
    assert        "./ineo update ${params[i]}" \
"
  ${PURPLE}Error -> Invalid argument or option ${BOLD}${params[i+1]}

  ${NF}View help about the command ${UNDERLINE}update${NF} typing:
    ${CYAN}ineo help update${NF}
"
  done

  assert_end UpdateWithIncorrectParameters
}
tests+=('UpdateWithIncorrectParameters')


UpdateCorrectly() {
  setup "${FUNCNAME[0]}"

  # Make an installation
  assert_raises "./ineo install -d $(pwd)/ineo_for_test" 0
  assert_raises "./ineo update" 0

  setup "${FUNCNAME[0]}"
  assert_raises "./ineo install -d $(pwd)/ineo_for_test" 0
  old_version=$(sed -n '/^VERSION=\(.*\)$/s//\1/p' $INEO_HOME/bin/ineo)

  assert "./ineo update" \
"
  ${GREEN}Ineo was successfully upgraded from ${BOLD}$old_version${GREEN} to ${BOLD}x.x.x${NF}
"

  assert_raises "test $(sed -n '/^VERSION=\(.*\)$/s//\1/p' $INEO_HOME/bin/ineo) = 'x.x.x'" 0

  assert_end UpdateCorrectly
}
tests+=('UpdateCorrectly')


if [[ -z "$test_name" ]]; then
  for test in "${tests[@]}"; do
    "$test"
  done
  echo -e "\nTests executed in ${SECONDS}sec"
else
  "$test_name"
fi

# vim: syntax=sh ts=2 sw=2 et sr softtabstop=2