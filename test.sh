#!/bin/bash

NEO4J_HOSTNAME='http://dist.neo4j.org'
DEFAULT_VERSION='all'
DEFAULT_EDITION='all'
LAST_VERSION='3.3.1'

# Regular Colors
BLACK='\033[0;30m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[0;37m'

# Underline
UNDERLINE='\033[4m'
ITALIC='\033[3m'
BOLD='\033[1m'

# No Format
NF='\033[0m'

# ==============================================================================
# PROVISION
# ==============================================================================

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
  if [[ "${java_version%*.*}" < "1.8" ]]; then
    versions=(1.9.9 2.3.6 3.0.3 3.3.1)
  else
    # neo4j 1.9.x is not compatible with java >= 1.8
    versions=(2.3.6 3.0.3 3.3.1)
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

# ==============================================================================
# PID FUNCTIONS
# ==============================================================================

function set_instance_pid {
  local instance_name=$1
  if [ -f $INEO_HOME/instances/$instance_name/data/neo4j-service.pid ]; then
    assert_raises \
      "test -f $INEO_HOME/instances/$instance_name/data/neo4j-service.pid" 0
    pid=$(head -n 1 $INEO_HOME/instances/$instance_name/data/neo4j-service.pid)
  else
    assert_raises \
      "test -f $INEO_HOME/instances/$instance_name/run/neo4j.pid" 0
    pid=$(head -n 1 $INEO_HOME/instances/$instance_name/run/neo4j.pid)
  fi
}

function assert_run_pid {
  local pid=$1
  # we need to wait some seconds, because on fast computers the pid will exists 
  # even though neo4j terminates due to a configuration error
  sleep 3 
  assert_raises "test $(ps -p $pid -o pid=)" 0
}

function assert_not_run_pid {
  local pid=$1
  # we need to wait some seconds, because on fast computers the pid will exists 
  # even though neo4j terminates due to a configuration error
  sleep 3
  assert_raises "test $(ps -p $pid -o pid=)" 1
}

# ==============================================================================
# RESET FUNCTION
# ==============================================================================

function setup {
  if [[ "${verbose}" != "" ]]; then
    echo -e "\nStarting test $1"
  fi

  rm -fr ineo_for_test
  assert_raises "test -d ineo_for_test" 1
}

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
    setup "${FUNCNAME[0]}"

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

  # Ensure the bad tar version of neo4j was downloaded
  assert_raises \
    "test -f $(pwd)/ineo_for_test/neo4j/neo4j-community-$LAST_VERSION-unix.tar.gz" 0

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
      assert_run_pid $pid

      # status running
      assert "./ineo status twitter" \
        "$(get_running_message $version twitter $pid)"

      # restart
      assert_raises "./ineo restart twitter" 0
      set_instance_pid twitter
      assert_run_pid $pid

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
      assert_raises "./ineo create -p7474 -e $edition -v $version twitter" 0
      assert_raises "./ineo create -p8484 -e $edition -v $version facebook" 0

      # start
      assert_raises "echo -ne 'y\n' | ./ineo start" 0

      set_instance_pid twitter
      local pid_twitter=$pid
      assert_run_pid $pid_twitter

      set_instance_pid facebook
      local pid_facebook=$pid
      assert_run_pid $pid_facebook

      # status running
      assert "./ineo status" \
"$(get_running_message $version facebook $pid_facebook)
$(get_running_message $version twitter $pid_twitter)"

      # restart
      assert_raises "echo -ne 'y\n' | ./ineo restart" 0

      set_instance_pid twitter
      pid_twitter=$pid
      assert_run_pid $pid_twitter

      set_instance_pid facebook
      pid_facebook=$pid
      assert_run_pid $pid_facebook

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
      assert_run_pid $pid_twitter

      set_instance_pid facebook
      pid_facebook=$pid
      assert_run_pid $pid_facebook

      # status running
      assert "./ineo status" \
"$(get_running_message $version facebook $pid_facebook)
$(get_running_message $version twitter $pid_twitter)"

      # restart
      assert_raises "./ineo restart -q" 0

      set_instance_pid twitter
      pid_twitter=$pid
      assert_run_pid $pid_twitter

      set_instance_pid facebook
      pid_facebook=$pid
      assert_run_pid $pid_facebook

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
# TEST INSTANCES
# ==============================================================================

InstancesWithIncorrectParameters() {
  setup "${FUNCNAME[0]}"

  params=(
    'wrong'
    '-q'
  )

  local param
  for param in "${params[@]}"; do
    assert_raises "./ineo instances $param" 1
    assert        "./ineo instances $param" \
"
  ${PURPLE}Error -> Invalid argument or option ${BOLD}$param

  ${NF}View help about the command ${UNDERLINE}instances${NF} typing:
    ${CYAN}ineo help instances${NF}
"
  done

  assert_end InstancesWithIncorrectParameters
}
tests+=('InstancesWithIncorrectParameters')


InstancesCorrectly() {
  for version in "${versions[@]}"; do
    for edition in "${editions[@]}"; do
      setup "${FUNCNAME[0]} ${version}-${edition}"

      # Make an installation
      assert_raises "./ineo install -d $(pwd)/ineo_for_test" 0

      assert_raises "./ineo create -p7474 -s8484 -e $edition -v $version twitter" 0
      assert_raises "./ineo create -p7575 -s8585 -e $edition -v $version facebook" 0

      assert_raises "./ineo instances" 0
      if [ ${version%%.*} -lt 3 ]; then
        assert        "./ineo instances" \
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
        assert        "./ineo instances" \
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

  assert_end InstancesCorrectly
}
tests+=('InstancesCorrectly')


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
    ${CYAN}ineo instances${NF}
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
    ${CYAN}ineo instances${NF}
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

      assert_raises "echo -ne 'y\n' | ./ineo destroy twitter" 0

      assert_raises "./ineo create -e $edition -v $version twitter" 0
      assert "echo -ne 'y\n' | ./ineo destroy twitter" \
"
  ${YELLOW}Warning -> Destroying the instance ${RED}twitter${YELLOW} will remove all data for this instance${NF}



  ${GREEN}The instance ${BOLD}twitter${GREEN} was successfully destroyed.${NF}
"

      # Test confirming with an instance running

      assert_raises "./ineo create -e $edition -v $version twitter" 0
      assert_raises "./ineo start twitter" 0

      set_instance_pid twitter
      assert_run_pid $pid

      assert_raises "echo -ne 'y\ny\n' | ./ineo destroy twitter" 0

      assert_not_run_pid $pid

      # Test forcing without an instance running

      assert_raises "./ineo create -e $edition -v $version twitter" 0

      assert_raises "./ineo destroy -f twitter" 0

      assert_raises "./ineo create -e $edition -v $version twitter" 0
      assert "./ineo destroy -f twitter" \
"
  ${GREEN}The instance ${BOLD}twitter${GREEN} was successfully destroyed.${NF}
"

      # Test forcing with an instance running

      assert_raises "./ineo create -e $edition -v $version twitter" 0
      assert_raises "./ineo start twitter" 0

      set_instance_pid twitter
      assert_run_pid $pid

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
    ${CYAN}ineo instances${NF}
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
      assert_run_pid $pid

      assert_raises "./ineo backup -p /tmp/ineo$$.dump twitter" 0
      assert_raises "test -s /tmp/ineo$$.dump" 0
      rm /tmp/ineo$$.dump

      # check if instance was restarted after backup
      set_instance_pid twitter
      assert_run_pid $pid

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
  assert_run_pid $pid

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
        assert_run_pid $pid

        assert_raises "./ineo backup -p /tmp/ineo$$.dump twitter" 0
        assert_raises "test -s /tmp/ineo$$.dump" 0
      fi

      assert_raises "./ineo restore -f /tmp/ineo$$.dump twitter" 0


      # check if instance can be started after restore
      assert_raises "./ineo start twitter" 0
      set_instance_pid twitter
      assert_run_pid $pid

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
  assert_run_pid $pid

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
  assert_run_pid $pid

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
    ${CYAN}ineo instances${NF}
"

  assert_end ClearDataOnANonExistentInstance
}
tests+=('ClearDataOnANonExistentInstance')


ClearDataCorrectly() {
  local version
  for version in "${versions[@]}"; do
    for edition in "${editions[@]}"; do
      setup "${FUNCNAME[0]} ${version}-${edition}"

      # Make an installation
      assert_raises "./ineo install -d $(pwd)/ineo_for_test" 0

      # Test confirming without an instance running

      assert_raises "./ineo create -e $edition -v $version twitter" 0
      # Create a fake directory
      assert_raises "mkdir ineo_for_test/instances/twitter/data/graph.db" 0
      assert_raises "test -d ineo_for_test/instances/twitter/data/graph.db" 0

      assert_raises "echo -ne 'y\n' | ./ineo delete-db twitter" 0

      # Create a fake directory
      assert_raises "mkdir ineo_for_test/instances/twitter/data/graph.db" 0
      assert_raises "test -d ineo_for_test/instances/twitter/data/graph.db" 0

      assert "echo -ne 'y\n' | ./ineo delete-db twitter" \
"
  ${YELLOW}Warning -> ${RED}delete-db${YELLOW} on the instance ${BOLD}twitter${YELLOW} will remove all data for this instance${NF}


  ${GREEN}The data for the instance ${BOLD}twitter${GREEN} was successfully removed${NF}
"

      assert_raises "test -d ineo_for_test/instances/twitter/data/graph.db" 1

      # Test confirming with an instance running

      # Create a fake directory
      assert_raises "mkdir ineo_for_test/instances/twitter/data/graph.db" 0
      assert_raises "test -d ineo_for_test/instances/twitter/data/graph.db" 0

      assert_raises "./ineo start twitter" 0

      set_instance_pid twitter
      assert_run_pid $pid

      assert_raises "echo -ne 'y\ny\n' | ./ineo delete-db twitter" 0

      assert_raises "test -d ineo_for_test/instances/twitter/data/graph.db" 1

      assert_not_run_pid $pid

      # Test forcing without an instance running

      # Create a fake directory
      assert_raises "mkdir ineo_for_test/instances/twitter/data/graph.db" 0
      assert_raises "test -d ineo_for_test/instances/twitter/data/graph.db" 0

      assert_raises "./ineo delete-db -f twitter" 0

      assert_raises "test -d ineo_for_test/instances/twitter/data/graph.db" 1

      # Create a fake directory
      assert_raises "mkdir ineo_for_test/instances/twitter/data/graph.db" 0
      assert_raises "test -d ineo_for_test/instances/twitter/data/graph.db" 0

      assert "./ineo delete-db -f twitter" \
"
  ${GREEN}The data for the instance ${BOLD}twitter${GREEN} was successfully removed${NF}
"

      assert_raises "test -d ineo_for_test/instances/twitter/data/graph.db" 1

      # Test forcing with an instance running

      # Create a fake directory
      assert_raises "mkdir ineo_for_test/instances/twitter/data/graph.db" 0
      assert_raises "test -d ineo_for_test/instances/twitter/data/graph.db" 0

      assert_raises "./ineo start twitter" 0

      set_instance_pid twitter
      assert_run_pid $pid

      assert_raises "./ineo delete-db -f twitter" 0

      assert_not_run_pid $pid

      assert_raises "test -d ineo_for_test/instances/twitter/data/graph.db" 1
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
      assert_raises "test -d ineo_for_test/instances/twitter/data/graph.db" 1

      assert_raises "echo -ne 'y\n' | ./ineo delete-db twitter" 0

      assert "echo -ne 'y\n' | ./ineo delete-db twitter" \
"
  ${YELLOW}Warning -> ${RED}delete-db${YELLOW} on the instance ${BOLD}twitter${YELLOW} will remove all data for this instance${NF}


  There is not a database on the instance ${UNDERLINE}twitter${NF}, so nothing was removed
"

      # Test confirming with an instance running

      assert_raises "./ineo start twitter" 0

      set_instance_pid twitter
      assert_run_pid $pid

      assert_raises "echo -ne 'y\ny\n' | ./ineo delete-db twitter" 0

      assert_raises "test -d ineo_for_test/instances/twitter/data/graph.db" 1

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
      assert_run_pid $pid

      assert_raises "./ineo delete-db -f twitter" 0

      assert_not_run_pid $pid

      assert_raises "test -d ineo_for_test/instances/twitter/data/graph.db" 1
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
else
  "$test_name"
fi

# vim: syntax=sh ts=2 sw=2 et sr softtabstop=2
